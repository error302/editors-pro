use image::metadata::Orientation;
use image::{ImageDecoder, ImageReader, Limits};

use super::FrameData;

const MAX_IMAGE_DIMENSION: u32 = 16_384;
const MAX_DECODE_ALLOCATION: u64 = 256 * 1024 * 1024;
const MAX_FRAME_DIMENSION: u32 = 4_096;

pub fn dimensions(path: &str) -> Result<(u32, u32), String> {
    let reader = ImageReader::open(path)
        .map_err(|error| format!("Could not open image: {error}"))?
        .with_guessed_format()
        .map_err(|error| format!("Could not identify image format: {error}"))?;
    let mut decoder = reader
        .into_decoder()
        .map_err(|error| format!("Could not read image metadata: {error}"))?;
    let (width, height) = decoder.dimensions();
    validate_dimensions(width, height)?;
    let orientation = decoder.orientation().unwrap_or(Orientation::NoTransforms);

    if matches!(
        orientation,
        Orientation::Rotate90
            | Orientation::Rotate270
            | Orientation::Rotate90FlipH
            | Orientation::Rotate270FlipH
    ) {
        Ok((height, width))
    } else {
        Ok((width, height))
    }
}

fn validate_dimensions(width: u32, height: u32) -> Result<(), String> {
    if width == 0 || height == 0 || width > MAX_IMAGE_DIMENSION || height > MAX_IMAGE_DIMENSION {
        return Err(format!(
            "Image dimensions must be between 1 and {MAX_IMAGE_DIMENSION} pixels"
        ));
    }
    Ok(())
}

pub fn decode(path: &str) -> Result<FrameData, String> {
    let mut reader = ImageReader::open(path)
        .map_err(|error| format!("Could not open image: {error}"))?
        .with_guessed_format()
        .map_err(|error| format!("Could not identify image format: {error}"))?;

    let mut limits = Limits::default();
    limits.max_image_width = Some(MAX_IMAGE_DIMENSION);
    limits.max_image_height = Some(MAX_IMAGE_DIMENSION);
    limits.max_alloc = Some(MAX_DECODE_ALLOCATION);
    reader.limits(limits);

    let mut decoder = reader
        .into_decoder()
        .map_err(|error| format!("Could not read image: {error}"))?;
    let orientation = decoder.orientation().unwrap_or(Orientation::NoTransforms);
    let mut image = image::DynamicImage::from_decoder(decoder)
        .map_err(|error| format!("Could not decode image: {error}"))?;
    image.apply_orientation(orientation);
    if image.width() > MAX_FRAME_DIMENSION || image.height() > MAX_FRAME_DIMENSION {
        image = image.thumbnail(MAX_FRAME_DIMENSION, MAX_FRAME_DIMENSION);
    }
    let image = image.into_rgba8();
    let (width, height) = image.dimensions();

    Ok(FrameData {
        width,
        height,
        data: image.into_raw(),
        timestamp_ms: 0,
        is_keyframe: true,
        pooled: false,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use image::{Rgba, RgbaImage};

    #[test]
    fn decodes_rgba_pixels_and_reports_dimensions() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("still.png");
        RgbaImage::from_pixel(3, 2, Rgba([12, 34, 56, 255]))
            .save(&path)
            .unwrap();

        assert_eq!(dimensions(path.to_str().unwrap()).unwrap(), (3, 2));
        let frame = decode(path.to_str().unwrap()).unwrap();
        assert_eq!((frame.width, frame.height), (3, 2));
        assert_eq!(frame.data.len(), 3 * 2 * 4);
        assert_eq!(&frame.data[..4], &[12, 34, 56, 255]);
    }

    #[test]
    fn rejects_corrupt_image_data() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("broken.png");
        std::fs::write(&path, b"not an image").unwrap();

        assert!(decode(path.to_str().unwrap()).is_err());
    }
}
