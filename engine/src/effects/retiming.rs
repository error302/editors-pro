//! Retiming / Speed Ramp — 7 interpolation types, optical flow estimation, frame interpolation.
//!
//! Professional speed ramping with bezier curves, optical flow for smooth slow motion,
//! and multiple frame interpolation methods.

use serde::{Deserialize, Serialize};

/// Speed ramp interpolation type.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum RampInterpolation {
    Linear,
    Bezier,
    SmoothStep,
    EaseIn,
    EaseOut,
    EaseInOut,
    CatmullRom,
}

/// A single control point on the speed ramp curve.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SpeedPoint {
    pub time: f64,           // Position on timeline (seconds)
    pub speed: f64,          // Speed multiplier at this point (0.1..10.0)
    pub interpolation: RampInterpolation,
    pub bezier_handle_in: (f64, f64),  // (time_offset, speed_offset)
    pub bezier_handle_out: (f64, f64),
}

impl SpeedPoint {
    pub fn new(time: f64, speed: f64) -> Self {
        Self {
            time, speed,
            interpolation: RampInterpolation::Linear,
            bezier_handle_in: (-0.1, 0.0),
            bezier_handle_out: (0.1, 0.0),
        }
    }

    pub fn with_bezier(mut self, hix: f64, hiy: f64, hox: f64, hoy: f64) -> Self {
        self.bezier_handle_in = (hix, hiy);
        self.bezier_handle_out = (hox, hoy);
        self
    }
}

/// Speed ramp curve defined by control points.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SpeedRamp {
    pub points: Vec<SpeedPoint>,
}

impl SpeedRamp {
    pub fn new() -> Self {
        Self { points: vec![SpeedPoint::new(0.0, 1.0)] }
    }

    pub fn constant(speed: f64) -> Self {
        Self { points: vec![SpeedPoint::new(0.0, speed)] }
    }

    /// Add a control point, keeping them sorted by time.
    pub fn add_point(&mut self, point: SpeedPoint) {
        self.points.push(point);
        self.points.sort_by(|a, b| a.time.partial_cmp(&b.time).unwrap());
    }

    /// Remove the point at the given index.
    pub fn remove_point(&mut self, index: usize) -> Option<SpeedPoint> {
        if self.points.len() <= 1 { return None; }
        if index < self.points.len() { Some(self.points.remove(index)) } else { None }
    }

    /// Evaluate speed at a given time by interpolating between control points.
    pub fn evaluate_at(&self, time: f64) -> f64 {
        if self.points.is_empty() { return 1.0; }
        if self.points.len() == 1 { return self.points[0].speed; }

        // Find surrounding points
        if time <= self.points[0].time { return self.points[0].speed; }
        if time >= self.points[self.points.len()-1].time { return self.points[self.points.len()-1].speed; }

        for i in 0..self.points.len()-1 {
            if time >= self.points[i].time && time <= self.points[i+1].time {
                let p0 = &self.points[i];
                let p1 = &self.points[i+1];
                let t = (time - p0.time) / (p1.time - p0.time + 1e-10);
                let t = t.clamp(0.0, 1.0);

                return match p0.interpolation {
                    RampInterpolation::Linear => p0.speed + (p1.speed - p0.speed) * t,
                    RampInterpolation::Bezier => {
                        let p0y = p0.speed;
                        let p1y = p1.speed;
                        let cp0y = p0.speed + p0.bezier_handle_out.1;
                        let cp1y = p1.speed + p1.bezier_handle_in.1;
                        cubic_bezier_1d(p0y as f32, cp0y as f32, cp1y as f32, p1y as f32, t as f32) as f64
                    }
                    RampInterpolation::SmoothStep => {
                        let t = t * t * (3.0 - 2.0 * t);
                        p0.speed + (p1.speed - p0.speed) * t
                    }
                    RampInterpolation::EaseIn => {
                        let t = t * t;
                        p0.speed + (p1.speed - p0.speed) * t
                    }
                    RampInterpolation::EaseOut => {
                        let t = 1.0 - (1.0 - t) * (1.0 - t);
                        p0.speed + (p1.speed - p0.speed) * t
                    }
                    RampInterpolation::EaseInOut => {
                        let t = if t < 0.5 { 2.0 * t * t } else { 1.0 - (-2.0 * t + 2.0).powi(2) / 2.0 };
                        p0.speed + (p1.speed - p0.speed) * t
                    }
                    RampInterpolation::CatmullRom => {
                        let p_prev = if i > 0 { self.points[i-1].speed } else { p0.speed };
                        let p_next = if i + 2 < self.points.len() { self.points[i+2].speed } else { p1.speed };
                        catmull_rom_1d(p_prev as f32, p0.speed as f32, p1.speed as f32, p_next as f32, t as f32) as f64
                    }
                };
            }
        }
        1.0
    }

    /// Map timeline time to source time using the speed ramp.
    /// This integrates the speed curve to get cumulative source position.
    pub fn timeline_to_source_time(&self, timeline_time: f64) -> f64 {
        let steps = 1000;
        let duration = timeline_time;
        let dt = duration / steps as f64;
        let mut source_time = 0.0;
        for i in 0..steps {
            let t = i as f64 * dt;
            let speed = self.evaluate_at(t);
            source_time += dt / speed.max(0.01);
        }
        source_time
    }

    /// Get the total source duration for a given timeline duration.
    pub fn source_duration(&self, timeline_duration: f64) -> f64 {
        self.timeline_to_source_time(timeline_duration)
    }
}

/// 1D cubic Bezier evaluation.
fn cubic_bezier_1d(p0: f32, p1: f32, p2: f32, p3: f32, t: f32) -> f32 {
    let u = 1.0 - t;
    u*u*u*p0 + 3.0*u*u*t*p1 + 3.0*u*t*t*p2 + t*t*t*p3
}

/// 1D Catmull-Rom spline evaluation.
fn catmull_rom_1d(p0: f32, p1: f32, p2: f32, p3: f32, t: f32) -> f32 {
    let t2 = t * t;
    let t3 = t2 * t;
    0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0*p0 - 5.0*p1 + 4.0*p2 - p3) * t2 + (-p0 + 3.0*p1 - 3.0*p2 + p3) * t3)
}

/// Frame interpolation method for slow motion.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum FrameInterpolation {
    None,           // Frame duplication
    Blend,          // Simple cross-fade
    OpticalFlow,    // Motion-compensated interpolation
}

/// Optical flow vector for a block.
#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub struct FlowVector {
    pub x: i32,
    pub y: i32,
    pub dx: f32,
    pub dy: f32,
    pub confidence: f32,
}

/// Simple block-matching optical flow estimation.
pub fn estimate_optical_flow(
    frame_a: &[u8], frame_b: &[u8],
    width: u32, height: u32,
    block_size: u32, search_range: u32,
) -> Vec<FlowVector> {
    let mut vectors = Vec::new();
    let bs = block_size as i32;
    let sr = search_range as i32;

    for by in (0..height as i32).step_by(bs as usize) {
        for bx in (0..width as i32).step_by(bs as usize) {
            let mut best_dx = 0.0f32;
            let mut best_dy = 0.0f32;
            let mut best_sad = i64::MAX;

            for dy in -sr..=sr {
                for dx in -sr..=sr {
                    let mut sad = 0i64;
                    for py in 0..bs {
                        for px in 0..bs {
                            let ax = (bx + px).clamp(0, width as i32 - 1) as u32;
                            let ay = (by + py).clamp(0, height as i32 - 1) as u32;
                            let bxx = (bx + px + dx).clamp(0, width as i32 - 1) as u32;
                            let byy = (by + py + dy).clamp(0, height as i32 - 1) as u32;
                            let a_idx = ((ay * width + ax) * 4) as usize;
                            let b_idx = ((byy * width + bxx) * 4) as usize;
                            sad += (frame_a[a_idx] as i64 - frame_b[b_idx] as i64).abs();
                        }
                    }
                    if sad < best_sad {
                        best_sad = sad;
                        best_dx = dx as f32;
                        best_dy = dy as f32;
                    }
                }
            }

            let confidence = 1.0 - (best_sad as f32 / (bs * bs * 255 * 4) as f32);
            vectors.push(FlowVector { x: bx, y: by, dx: best_dx, dy: best_dy, confidence });
        }
    }
    vectors
}

/// Interpolate a frame between two frames using optical flow.
pub fn interpolate_frame(
    frame_a: &[u8], frame_b: &[u8],
    flow_ab: &[FlowVector],
    width: u32, height: u32,
    t: f32, // 0.0 = frame_a, 1.0 = frame_b
) -> Vec<u8> {
    let mut output = vec![0u8; (width * height * 4) as usize];
    let bs = 16i32; // Block size used for flow

    for y in 0..height {
        for x in 0..width {
            let idx = ((y * width + x) * 4) as usize;

            // Find the flow vector for this block
            let bx = (x as i32 / bs) * bs;
            let by = (y as i32 / bs) * bs;
            let flow = flow_ab.iter().find(|v| v.x == bx && v.y == by);

            let (dx, dy) = flow.map(|v| (v.dx * t, v.dy * t)).unwrap_or((0.0, 0.0));

            // Sample from frame_a at warped position
            let src_ax = (x as f32 + dx).clamp(0.0, width as f32 - 1.0) as u32;
            let src_ay = (y as f32 + dy).clamp(0.0, height as f32 - 1.0) as u32;
            let a_idx = ((src_ay * width + src_ax) * 4) as usize;

            // Sample from frame_b at backward-warped position
            let src_bx = (x as f32 - dx).clamp(0.0, width as f32 - 1.0) as u32;
            let src_by = (y as f32 - dy).clamp(0.0, height as f32 - 1.0) as u32;
            let b_idx = ((src_by * width + src_bx) * 4) as usize;

            // Blend
            for c in 0..4 {
                let a = frame_a.get(a_idx + c).copied().unwrap_or(0);
                let b = frame_b.get(b_idx + c).copied().unwrap_or(0);
                output[idx + c] = (a as f32 * (1.0 - t) + b as f32 * t) as u8;
            }
        }
    }
    output
}

/// Interpolate a frame using simple blending (no optical flow).
pub fn blend_frames(frame_a: &[u8], frame_b: &[u8], t: f32) -> Vec<u8> {
    frame_a.iter().zip(frame_b.iter())
        .map(|(a, b)| (*a as f32 * (1.0 - t) + *b as f32 * t) as u8)
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_speed_ramp_new() {
        let ramp = SpeedRamp::new();
        assert_eq!(ramp.points.len(), 1);
        assert_eq!(ramp.evaluate_at(0.0), 1.0);
    }

    #[test]
    fn test_speed_ramp_constant() {
        let ramp = SpeedRamp::constant(2.0);
        assert_eq!(ramp.evaluate_at(5.0), 2.0);
    }

    #[test]
    fn test_speed_ramp_linear() {
        let mut ramp = SpeedRamp::new();
        ramp.add_point(SpeedPoint::new(0.0, 1.0));
        ramp.add_point(SpeedPoint::new(10.0, 2.0));
        let mid = ramp.evaluate_at(5.0);
        assert!((mid - 1.5).abs() < 0.01);
    }

    #[test]
    fn test_speed_ramp_bezier() {
        let mut ramp = SpeedRamp::new();
        ramp.add_point(SpeedPoint::new(0.0, 1.0).with_bezier(-0.1, 0.0, 0.1, 0.5));
        ramp.add_point(SpeedPoint::new(10.0, 2.0).with_bezier(-0.1, -0.5, 0.1, 0.0));
        let val = ramp.evaluate_at(5.0);
        assert!(val > 0.0 && val < 3.0);
    }

    #[test]
    fn test_speed_ramp_smooth_step() {
        let mut ramp = SpeedRamp::new();
        let mut p0 = SpeedPoint::new(0.0, 1.0);
        p0.interpolation = RampInterpolation::SmoothStep;
        ramp.add_point(p0);
        ramp.add_point(SpeedPoint::new(10.0, 2.0));
        let val = ramp.evaluate_at(5.0);
        assert!(val > 0.0 && val < 3.0);
    }

    #[test]
    fn test_speed_ramp_ease_in() {
        let mut ramp = SpeedRamp::new();
        let mut p0 = SpeedPoint::new(0.0, 1.0);
        p0.interpolation = RampInterpolation::EaseIn;
        ramp.add_point(p0);
        ramp.add_point(SpeedPoint::new(10.0, 2.0));
        let early = ramp.evaluate_at(2.0);
        let late = ramp.evaluate_at(8.0);
        assert!(early < late);
    }

    #[test]
    fn test_speed_ramp_ease_out() {
        let mut ramp = SpeedRamp::new();
        let mut p0 = SpeedPoint::new(0.0, 1.0);
        p0.interpolation = RampInterpolation::EaseOut;
        ramp.add_point(p0);
        ramp.add_point(SpeedPoint::new(10.0, 2.0));
        let val = ramp.evaluate_at(5.0);
        assert!(val > 1.0);
    }

    #[test]
    fn test_speed_ramp_ease_in_out() {
        let mut ramp = SpeedRamp::new();
        let mut p0 = SpeedPoint::new(0.0, 1.0);
        p0.interpolation = RampInterpolation::EaseInOut;
        ramp.add_point(p0);
        ramp.add_point(SpeedPoint::new(10.0, 2.0));
        let mid = ramp.evaluate_at(5.0);
        assert!((mid - 1.5).abs() < 0.1);
    }

    #[test]
    fn test_speed_ramp_catmull_rom() {
        let mut ramp = SpeedRamp::new();
        ramp.add_point(SpeedPoint::new(0.0, 1.0));
        let mut p1 = SpeedPoint::new(5.0, 2.0);
        p1.interpolation = RampInterpolation::CatmullRom;
        ramp.add_point(p1);
        ramp.add_point(SpeedPoint::new(10.0, 1.0));
        let val = ramp.evaluate_at(5.0);
        assert!((val - 2.0).abs() < 0.01);
    }

    #[test]
    fn test_add_point_sorted() {
        let mut ramp = SpeedRamp::new();
        ramp.add_point(SpeedPoint::new(10.0, 2.0));
        ramp.add_point(SpeedPoint::new(5.0, 1.5));
        assert_eq!(ramp.points[0].time, 0.0);
        assert_eq!(ramp.points[1].time, 5.0);
        assert_eq!(ramp.points[2].time, 10.0);
    }

    #[test]
    fn test_remove_point() {
        let mut ramp = SpeedRamp::new();
        ramp.add_point(SpeedPoint::new(5.0, 2.0));
        ramp.add_point(SpeedPoint::new(10.0, 1.5));
        let removed = ramp.remove_point(1);
        assert!(removed.is_some());
        assert_eq!(ramp.points.len(), 2);
    }

    #[test]
    fn test_remove_last_point_fails() {
        let mut ramp = SpeedRamp::new();
        assert!(ramp.remove_point(0).is_none());
    }

    #[test]
    fn test_timeline_to_source_time() {
        let ramp = SpeedRamp::constant(2.0);
        let source = ramp.timeline_to_source_time(10.0);
        assert!((source - 5.0).abs() < 1.0); // 2x speed = half source time
    }

    #[test]
    fn test_blend_frames() {
        let a = vec![100u8; 16];
        let b = vec![200u8; 16];
        let result = blend_frames(&a, &b, 0.5);
        assert_eq!(result[0], 150);
    }

    #[test]
    fn test_interpolate_frame() {
        let a = vec![100u8; 10 * 10 * 4];
        let b = vec![200u8; 10 * 10 * 4];
        let flow = vec![];
        let result = interpolate_frame(&a, &b, &flow, 10, 10, 0.5);
        assert_eq!(result.len(), 400);
    }

    #[test]
    fn test_speed_point_constructor() {
        let p = SpeedPoint::new(5.0, 2.0);
        assert_eq!(p.time, 5.0);
        assert_eq!(p.speed, 2.0);
        assert_eq!(p.interpolation, RampInterpolation::Linear);
    }

    #[test]
    fn test_speed_point_bezier_handles() {
        let p = SpeedPoint::new(5.0, 2.0).with_bezier(-0.2, -0.1, 0.2, 0.1);
        assert_eq!(p.bezier_handle_in, (-0.2, -0.1));
        assert_eq!(p.bezier_handle_out, (0.2, 0.1));
    }

    #[test]
    fn test_ramp_before_first_point() {
        let mut ramp = SpeedRamp::new();
        ramp.add_point(SpeedPoint::new(5.0, 2.0));
        assert_eq!(ramp.evaluate_at(-1.0), 1.0);
    }

    #[test]
    fn test_ramp_after_last_point() {
        let mut ramp = SpeedRamp::new();
        ramp.add_point(SpeedPoint::new(5.0, 2.0));
        ramp.add_point(SpeedPoint::new(10.0, 3.0));
        assert_eq!(ramp.evaluate_at(15.0), 3.0);
    }
}
