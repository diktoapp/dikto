use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use ringbuf::traits::{Consumer, Observer, Producer, Split};
use ringbuf::{HeapCons, HeapProd, HeapRb};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use thiserror::Error;
use tracing::{error, info};

#[derive(Debug, Error)]
pub enum AudioError {
    #[error("No input device available")]
    NoInputDevice,
    #[error("No supported input config")]
    NoSupportedConfig,
    #[error("Failed to build stream: {0}")]
    StreamBuild(String),
    #[error("Failed to play stream: {0}")]
    StreamPlay(String),
    #[error("Device error: {0}")]
    Device(String),
}

/// Configuration for audio capture.
#[derive(Debug, Clone)]
pub struct AudioCaptureConfig {
    /// Target sample rate (always 16000 for whisper)
    pub target_sample_rate: u32,
    /// Ring buffer capacity in samples
    pub buffer_capacity: usize,
}

impl Default for AudioCaptureConfig {
    fn default() -> Self {
        Self {
            target_sample_rate: 16000,
            // 30 seconds at 16kHz
            buffer_capacity: 16000 * 30,
        }
    }
}

/// Handle to a running audio capture session.
pub struct AudioCapture {
    _stream: cpal::Stream,
    consumer: HeapCons<f32>,
    running: Arc<AtomicBool>,
}

impl AudioCapture {
    /// Start capturing audio from the default input device.
    pub fn start(config: AudioCaptureConfig) -> Result<Self, AudioError> {
        let host = cpal::default_host();
        let device = host
            .default_input_device()
            .ok_or(AudioError::NoInputDevice)?;

        let device_name = device.name().unwrap_or_else(|_| "unknown".to_string());
        info!("Using input device: {device_name}");

        let supported_config = device
            .default_input_config()
            .map_err(|_| AudioError::NoSupportedConfig)?;

        let device_sample_rate = supported_config.sample_rate().0;
        let device_channels = supported_config.channels();
        info!("Device config: {device_sample_rate}Hz, {device_channels}ch, {:?}", supported_config.sample_format());

        let rb = HeapRb::<f32>::new(config.buffer_capacity);
        let (producer, consumer) = rb.split();

        let running = Arc::new(AtomicBool::new(true));
        let running_clone = running.clone();

        let target_rate = config.target_sample_rate;

        let stream = build_stream(
            &device,
            &supported_config,
            producer,
            running_clone,
            target_rate,
            device_channels,
            device_sample_rate,
        )?;

        stream
            .play()
            .map_err(|e| AudioError::StreamPlay(e.to_string()))?;

        info!("Audio capture started");

        Ok(Self {
            _stream: stream,
            consumer,
            running,
        })
    }

    /// Read available samples from the ring buffer.
    /// Returns a Vec of f32 samples at the target sample rate (16kHz mono).
    pub fn read_samples(&mut self) -> Vec<f32> {
        let available = self.consumer.occupied_len();
        if available == 0 {
            return Vec::new();
        }
        let mut buf = vec![0.0f32; available];
        let read = self.consumer.pop_slice(&mut buf);
        buf.truncate(read);
        buf
    }

    /// Check if the capture is still running.
    pub fn is_running(&self) -> bool {
        self.running.load(Ordering::Relaxed)
    }

    /// Stop the capture.
    pub fn stop(&self) {
        self.running.store(false, Ordering::Relaxed);
        info!("Audio capture stopped");
    }
}

impl Drop for AudioCapture {
    fn drop(&mut self) {
        self.stop();
    }
}

/// Build a cpal input stream that writes resampled mono samples into the ring buffer.
fn build_stream(
    device: &cpal::Device,
    config: &cpal::SupportedStreamConfig,
    mut producer: HeapProd<f32>,
    running: Arc<AtomicBool>,
    target_rate: u32,
    channels: u16,
    device_rate: u32,
) -> Result<cpal::Stream, AudioError> {
    let sample_format = config.sample_format();
    let stream_config: cpal::StreamConfig = config.clone().into();

    // Resampling state: we use linear interpolation for downsampling
    let ratio = device_rate as f64 / target_rate as f64;
    let mut resample_pos: f64 = 0.0;

    macro_rules! build_input_stream {
        ($sample_type:ty, $to_f32:expr) => {{
            device
                .build_input_stream(
                    &stream_config,
                    move |data: &[$sample_type], _: &cpal::InputCallbackInfo| {
                        if !running.load(Ordering::Relaxed) {
                            return;
                        }

                        // Convert to mono f32
                        let mono: Vec<f32> = data
                            .chunks(channels as usize)
                            .map(|frame| {
                                let sum: f32 = frame.iter().map(|s| $to_f32(*s)).sum();
                                sum / channels as f32
                            })
                            .collect();

                        // Resample to target rate using linear interpolation
                        if device_rate == target_rate {
                            // No resampling needed
                            let _ = producer.push_slice(&mono);
                        } else {
                            let mut resampled = Vec::new();
                            while (resample_pos as usize) < mono.len().saturating_sub(1) {
                                let idx = resample_pos as usize;
                                let frac = resample_pos - idx as f64;
                                let sample = mono[idx] * (1.0 - frac as f32)
                                    + mono[idx + 1] * frac as f32;
                                resampled.push(sample);
                                resample_pos += ratio;
                            }
                            resample_pos -= mono.len() as f64;
                            if resample_pos < 0.0 {
                                resample_pos = 0.0;
                            }
                            let _ = producer.push_slice(&resampled);
                        }
                    },
                    move |err| {
                        error!("Audio input error: {err}");
                    },
                    None,
                )
                .map_err(|e| AudioError::StreamBuild(e.to_string()))?
        }};
    }

    let stream = match sample_format {
        cpal::SampleFormat::F32 => build_input_stream!(f32, |s: f32| s),
        cpal::SampleFormat::I16 => {
            build_input_stream!(i16, |s: i16| s as f32 / i16::MAX as f32)
        }
        cpal::SampleFormat::U16 => {
            build_input_stream!(u16, |s: u16| (s as f32 / u16::MAX as f32) * 2.0 - 1.0)
        }
        _ => {
            return Err(AudioError::StreamBuild(format!(
                "Unsupported sample format: {sample_format:?}"
            )));
        }
    };

    Ok(stream)
}
