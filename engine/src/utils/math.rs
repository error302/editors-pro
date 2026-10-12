use serde::{Deserialize, Serialize};
use std::ops::{Add, AddAssign, Div, DivAssign, Mul, MulAssign, Neg, Sub, SubAssign};

// ─── Basic interpolation helpers ─────────────────────────────────────────────

#[inline]
pub fn lerp(a: f64, b: f64, t: f64) -> f64 {
    a + (b - a) * t
}

#[inline]
pub fn inverse_lerp(a: f64, b: f64, value: f64) -> f64 {
    if (b - a).abs() < f64::EPSILON {
        0.0
    } else {
        ((value - a) / (b - a)).clamp(0.0, 1.0)
    }
}

#[inline]
pub fn clamp<T: PartialOrd>(value: T, min: T, max: T) -> T {
    if value < min {
        min
    } else if value > max {
        max
    } else {
        value
    }
}

#[inline]
pub fn smoothstep(edge0: f64, edge1: f64, x: f64) -> f64 {
    let t = ((x - edge0) / (edge1 - edge0)).clamp(0.0, 1.0);
    t * t * (3.0 - 2.0 * t)
}

#[inline]
pub fn smootherstep(edge0: f64, edge1: f64, x: f64) -> f64 {
    let t = ((x - edge0) / (edge1 - edge0)).clamp(0.0, 1.0);
    t * t * t * (t * (t * 6.0 - 15.0) + 10.0)
}

// ─── Vector types ────────────────────────────────────────────────────────────

#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub struct Vector2f {
    pub x: f32,
    pub y: f32,
}

impl Vector2f {
    pub const ZERO: Self = Self { x: 0.0, y: 0.0 };
    pub const ONE: Self = Self { x: 1.0, y: 1.0 };

    pub fn new(x: f32, y: f32) -> Self {
        Self { x, y }
    }

    pub fn dot(self, other: Self) -> f32 {
        self.x * other.x + self.y * other.y
    }

    pub fn length(self) -> f32 {
        self.dot(self).sqrt()
    }

    pub fn normalized(self) -> Self {
        let len = self.length();
        if len < f32::EPSILON {
            Self::ZERO
        } else {
            self / len
        }
    }

    pub fn distance(self, other: Self) -> f32 {
        (self - other).length()
    }
}

impl Add for Vector2f {
    type Output = Self;
    fn add(self, rhs: Self) -> Self {
        Self::new(self.x + rhs.x, self.y + rhs.y)
    }
}

impl Sub for Vector2f {
    type Output = Self;
    fn sub(self, rhs: Self) -> Self {
        Self::new(self.x - rhs.x, self.y - rhs.y)
    }
}

impl Mul<f32> for Vector2f {
    type Output = Self;
    fn mul(self, rhs: f32) -> Self {
        Self::new(self.x * rhs, self.y * rhs)
    }
}

impl Div<f32> for Vector2f {
    type Output = Self;
    fn div(self, rhs: f32) -> Self {
        Self::new(self.x / rhs, self.y / rhs)
    }
}

impl Neg for Vector2f {
    type Output = Self;
    fn neg(self) -> Self {
        Self::new(-self.x, -self.y)
    }
}

impl AddAssign for Vector2f {
    fn add_assign(&mut self, rhs: Self) {
        self.x += rhs.x;
        self.y += rhs.y;
    }
}

impl SubAssign for Vector2f {
    fn sub_assign(&mut self, rhs: Self) {
        self.x -= rhs.x;
        self.y -= rhs.y;
    }
}

impl MulAssign<f32> for Vector2f {
    fn mul_assign(&mut self, rhs: f32) {
        self.x *= rhs;
        self.y *= rhs;
    }
}

impl DivAssign<f32> for Vector2f {
    fn div_assign(&mut self, rhs: f32) {
        self.x /= rhs;
        self.y /= rhs;
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub struct Vector3f {
    pub x: f32,
    pub y: f32,
    pub z: f32,
}

impl Vector3f {
    pub const ZERO: Self = Self { x: 0.0, y: 0.0, z: 0.0 };
    pub const ONE: Self = Self { x: 1.0, y: 1.0, z: 1.0 };

    pub fn new(x: f32, y: f32, z: f32) -> Self {
        Self { x, y, z }
    }

    pub fn dot(self, other: Self) -> f32 {
        self.x * other.x + self.y * other.y + self.z * other.z
    }

    pub fn cross(self, other: Self) -> Self {
        Self::new(
            self.y * other.z - self.z * other.y,
            self.z * other.x - self.x * other.z,
            self.x * other.y - self.y * other.x,
        )
    }

    pub fn length(self) -> f32 {
        self.dot(self).sqrt()
    }

    pub fn normalized(self) -> Self {
        let len = self.length();
        if len < f32::EPSILON {
            Self::ZERO
        } else {
            self / len
        }
    }

    pub fn distance(self, other: Self) -> f32 {
        (self - other).length()
    }
}

impl Add for Vector3f {
    type Output = Self;
    fn add(self, rhs: Self) -> Self {
        Self::new(self.x + rhs.x, self.y + rhs.y, self.z + rhs.z)
    }
}

impl Sub for Vector3f {
    type Output = Self;
    fn sub(self, rhs: Self) -> Self {
        Self::new(self.x - rhs.x, self.y - rhs.y, self.z - rhs.z)
    }
}

impl Mul<f32> for Vector3f {
    type Output = Self;
    fn mul(self, rhs: f32) -> Self {
        Self::new(self.x * rhs, self.y * rhs, self.z * rhs)
    }
}

impl Div<f32> for Vector3f {
    type Output = Self;
    fn div(self, rhs: f32) -> Self {
        Self::new(self.x / rhs, self.y / rhs, self.z / rhs)
    }
}

impl Neg for Vector3f {
    type Output = Self;
    fn neg(self) -> Self {
        Self::new(-self.x, -self.y, -self.z)
    }
}

impl AddAssign for Vector3f {
    fn add_assign(&mut self, rhs: Self) {
        self.x += rhs.x;
        self.y += rhs.y;
        self.z += rhs.z;
    }
}

impl SubAssign for Vector3f {
    fn sub_assign(&mut self, rhs: Self) {
        self.x -= rhs.x;
        self.y -= rhs.y;
        self.z -= rhs.z;
    }
}

impl MulAssign<f32> for Vector3f {
    fn mul_assign(&mut self, rhs: f32) {
        self.x *= rhs;
        self.y *= rhs;
        self.z *= rhs;
    }
}

impl DivAssign<f32> for Vector3f {
    fn div_assign(&mut self, rhs: f32) {
        self.x /= rhs;
        self.y /= rhs;
        self.z /= rhs;
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub struct Vector4f {
    pub x: f32,
    pub y: f32,
    pub z: f32,
    pub w: f32,
}

impl Vector4f {
    pub const ZERO: Self = Self { x: 0.0, y: 0.0, z: 0.0, w: 0.0 };
    pub const ONE: Self = Self { x: 1.0, y: 1.0, z: 1.0, w: 1.0 };

    pub fn new(x: f32, y: f32, z: f32, w: f32) -> Self {
        Self { x, y, z, w }
    }

    pub fn dot(self, other: Self) -> f32 {
        self.x * other.x + self.y * other.y + self.z * other.z + self.w * other.w
    }

    pub fn length(self) -> f32 {
        self.dot(self).sqrt()
    }

    pub fn normalized(self) -> Self {
        let len = self.length();
        if len < f32::EPSILON {
            Self::ZERO
        } else {
            self / len
        }
    }
}

impl Add for Vector4f {
    type Output = Self;
    fn add(self, rhs: Self) -> Self {
        Self::new(self.x + rhs.x, self.y + rhs.y, self.z + rhs.z, self.w + rhs.w)
    }
}

impl Sub for Vector4f {
    type Output = Self;
    fn sub(self, rhs: Self) -> Self {
        Self::new(self.x - rhs.x, self.y - rhs.y, self.z - rhs.z, self.w - rhs.w)
    }
}

impl Mul<f32> for Vector4f {
    type Output = Self;
    fn mul(self, rhs: f32) -> Self {
        Self::new(self.x * rhs, self.y * rhs, self.z * rhs, self.w * rhs)
    }
}

impl Div<f32> for Vector4f {
    type Output = Self;
    fn div(self, rhs: f32) -> Self {
        Self::new(self.x / rhs, self.y / rhs, self.z / rhs, self.w / rhs)
    }
}

impl Neg for Vector4f {
    type Output = Self;
    fn neg(self) -> Self {
        Self::new(-self.x, -self.y, -self.z, -self.w)
    }
}

impl AddAssign for Vector4f {
    fn add_assign(&mut self, rhs: Self) {
        self.x += rhs.x;
        self.y += rhs.y;
        self.z += rhs.z;
        self.w += rhs.w;
    }
}

impl SubAssign for Vector4f {
    fn sub_assign(&mut self, rhs: Self) {
        self.x -= rhs.x;
        self.y -= rhs.y;
        self.z -= rhs.z;
        self.w -= rhs.w;
    }
}

impl MulAssign<f32> for Vector4f {
    fn mul_assign(&mut self, rhs: f32) {
        self.x *= rhs;
        self.y *= rhs;
        self.z *= rhs;
        self.w *= rhs;
    }
}

impl DivAssign<f32> for Vector4f {
    fn div_assign(&mut self, rhs: f32) {
        self.x /= rhs;
        self.y /= rhs;
        self.z /= rhs;
        self.w /= rhs;
    }
}

// ─── Matrix types ────────────────────────────────────────────────────────────

#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub struct Matrix3x3 {
    pub m: [[f32; 3]; 3],
}

impl Matrix3x3 {
    pub const IDENTITY: Self = Self {
        m: [
            [1.0, 0.0, 0.0],
            [0.0, 1.0, 0.0],
            [0.0, 0.0, 1.0],
        ],
    };

    pub fn new(m: [[f32; 3]; 3]) -> Self {
        Self { m }
    }

    pub fn multiply(&self, other: &Self) -> Self {
        let mut result = [[0.0f32; 3]; 3];
        for i in 0..3 {
            for j in 0..3 {
                for k in 0..3 {
                    result[i][j] += self.m[i][k] * other.m[k][j];
                }
            }
        }
        Self::new(result)
    }

    pub fn transpose(&self) -> Self {
        let mut result = [[0.0f32; 3]; 3];
        for i in 0..3 {
            for j in 0..3 {
                result[i][j] = self.m[j][i];
            }
        }
        Self::new(result)
    }

    pub fn determinant(&self) -> f32 {
        self.m[0][0] * (self.m[1][1] * self.m[2][2] - self.m[1][2] * self.m[2][1])
            - self.m[0][1] * (self.m[1][0] * self.m[2][2] - self.m[1][2] * self.m[2][0])
            + self.m[0][2] * (self.m[1][0] * self.m[2][1] - self.m[1][1] * self.m[2][0])
    }

    pub fn inverse(&self) -> Option<Self> {
        let det = self.determinant();
        if det.abs() < f32::EPSILON {
            return None;
        }
        let inv_det = 1.0 / det;
        let m = self.m;
        let result = [
            [
                (m[1][1] * m[2][2] - m[1][2] * m[2][1]) * inv_det,
                (m[0][2] * m[2][1] - m[0][1] * m[2][2]) * inv_det,
                (m[0][1] * m[1][2] - m[0][2] * m[1][1]) * inv_det,
            ],
            [
                (m[1][2] * m[2][0] - m[1][0] * m[2][2]) * inv_det,
                (m[0][0] * m[2][2] - m[0][2] * m[2][0]) * inv_det,
                (m[0][2] * m[1][0] - m[0][0] * m[1][2]) * inv_det,
            ],
            [
                (m[1][0] * m[2][1] - m[1][1] * m[2][0]) * inv_det,
                (m[0][1] * m[2][0] - m[0][0] * m[2][1]) * inv_det,
                (m[0][0] * m[1][1] - m[0][1] * m[1][0]) * inv_det,
            ],
        ];
        Some(Self::new(result))
    }

    pub fn transform_vector(&self, v: Vector3f) -> Vector3f {
        Vector3f::new(
            self.m[0][0] * v.x + self.m[0][1] * v.y + self.m[0][2] * v.z,
            self.m[1][0] * v.x + self.m[1][1] * v.y + self.m[1][2] * v.z,
            self.m[2][0] * v.x + self.m[2][1] * v.y + self.m[2][2] * v.z,
        )
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub struct Matrix4x4 {
    pub m: [[f32; 4]; 4],
}

impl Matrix4x4 {
    pub const IDENTITY: Self = Self {
        m: [
            [1.0, 0.0, 0.0, 0.0],
            [0.0, 1.0, 0.0, 0.0],
            [0.0, 0.0, 1.0, 0.0],
            [0.0, 0.0, 0.0, 1.0],
        ],
    };

    pub fn new(m: [[f32; 4]; 4]) -> Self {
        Self { m }
    }

    pub fn multiply(&self, other: &Self) -> Self {
        let mut result = [[0.0f32; 4]; 4];
        for i in 0..4 {
            for j in 0..4 {
                for k in 0..4 {
                    result[i][j] += self.m[i][k] * other.m[k][j];
                }
            }
        }
        Self::new(result)
    }

    pub fn transpose(&self) -> Self {
        let mut result = [[0.0f32; 4]; 4];
        for i in 0..4 {
            for j in 0..4 {
                result[i][j] = self.m[j][i];
            }
        }
        Self::new(result)
    }

    pub fn determinant(&self) -> f32 {
        let m = self.m;
        let mut det = 0.0f32;
        for col in 0..4 {
            let sign = if col % 2 == 0 { 1.0f32 } else { -1.0f32 };
            det += sign * m[0][col] * self.cofactor(0, col);
        }
        det
    }

    fn cofactor(&self, row: usize, col: usize) -> f32 {
        let sub = self.submatrix(row, col);
        let det = sub[0][0] * (sub[1][1] * sub[2][2] - sub[1][2] * sub[2][1])
            - sub[0][1] * (sub[1][0] * sub[2][2] - sub[1][2] * sub[2][0])
            + sub[0][2] * (sub[1][0] * sub[2][1] - sub[1][1] * sub[2][0]);
        let sign = if (row + col) % 2 == 0 { 1.0f32 } else { -1.0f32 };
        sign * det
    }

    fn submatrix(&self, skip_row: usize, skip_col: usize) -> [[f32; 3]; 3] {
        let mut result = [[0.0f32; 3]; 3];
        let mut ri = 0;
        for i in 0..4 {
            if i == skip_row {
                continue;
            }
            let mut ci = 0;
            for j in 0..4 {
                if j == skip_col {
                    continue;
                }
                result[ri][ci] = self.m[i][j];
                ci += 1;
            }
            ri += 1;
        }
        result
    }

    pub fn inverse(&self) -> Option<Self> {
        let det = self.determinant();
        if det.abs() < f32::EPSILON {
            return None;
        }
        let inv_det = 1.0 / det;
        let mut result = [[0.0f32; 4]; 4];
        for i in 0..4 {
            for j in 0..4 {
                result[j][i] = self.cofactor(i, j) * inv_det;
            }
        }
        Some(Self::new(result))
    }

    pub fn transform_point(&self, v: Vector4f) -> Vector4f {
        Vector4f::new(
            self.m[0][0] * v.x + self.m[0][1] * v.y + self.m[0][2] * v.z + self.m[0][3] * v.w,
            self.m[1][0] * v.x + self.m[1][1] * v.y + self.m[1][2] * v.z + self.m[1][3] * v.w,
            self.m[2][0] * v.x + self.m[2][1] * v.y + self.m[2][2] * v.z + self.m[2][3] * v.w,
            self.m[3][0] * v.x + self.m[3][1] * v.y + self.m[3][2] * v.z + self.m[3][3] * v.w,
        )
    }

    pub fn translation(x: f32, y: f32, z: f32) -> Self {
        Self::new([
            [1.0, 0.0, 0.0, x],
            [0.0, 1.0, 0.0, y],
            [0.0, 0.0, 1.0, z],
            [0.0, 0.0, 0.0, 1.0],
        ])
    }

    pub fn scaling(x: f32, y: f32, z: f32) -> Self {
        Self::new([
            [x, 0.0, 0.0, 0.0],
            [0.0, y, 0.0, 0.0],
            [0.0, 0.0, z, 0.0],
            [0.0, 0.0, 0.0, 1.0],
        ])
    }

    pub fn rotation_z(angle_rad: f32) -> Self {
        let c = angle_rad.cos();
        let s = angle_rad.sin();
        Self::new([
            [c, -s, 0.0, 0.0],
            [s, c, 0.0, 0.0],
            [0.0, 0.0, 1.0, 0.0],
            [0.0, 0.0, 0.0, 1.0],
        ])
    }
}

// ─── Easing functions ────────────────────────────────────────────────────────

pub fn ease_in_quad(t: f64) -> f64 {
    t * t
}

pub fn ease_out_quad(t: f64) -> f64 {
    t * (2.0 - t)
}

pub fn ease_in_out_quad(t: f64) -> f64 {
    if t < 0.5 {
        2.0 * t * t
    } else {
        -1.0 + (4.0 - 2.0 * t) * t
    }
}

pub fn ease_in_cubic(t: f64) -> f64 {
    t * t * t
}

pub fn ease_out_cubic(t: f64) -> f64 {
    let t1 = t - 1.0;
    t1 * t1 * t1 + 1.0
}

pub fn ease_in_out_cubic(t: f64) -> f64 {
    if t < 0.5 {
        4.0 * t * t * t
    } else {
        (2.0 * t - 2.0) * (2.0 * t - 2.0) * (2.0 * t - 2.0) / 2.0 + 1.0
    }
}

pub fn ease_in_quart(t: f64) -> f64 {
    t * t * t * t
}

pub fn ease_out_quart(t: f64) -> f64 {
    let t1 = t - 1.0;
    1.0 - t1 * t1 * t1 * t1
}

pub fn ease_in_out_quart(t: f64) -> f64 {
    if t < 0.5 {
        8.0 * t * t * t * t
    } else {
        1.0 - 8.0 * (t - 1.0) * (t - 1.0) * (t - 1.0) * (t - 1.0)
    }
}

pub fn ease_in_quint(t: f64) -> f64 {
    t * t * t * t * t
}

pub fn ease_out_quint(t: f64) -> f64 {
    let t1 = t - 1.0;
    1.0 + t1 * t1 * t1 * t1 * t1
}

pub fn ease_in_out_quint(t: f64) -> f64 {
    if t < 0.5 {
        16.0 * t * t * t * t * t
    } else {
        1.0 + 16.0 * (t - 1.0) * (t - 1.0) * (t - 1.0) * (t - 1.0) * (t - 1.0)
    }
}

pub fn ease_in_sine(t: f64) -> f64 {
    1.0 - (t * std::f64::consts::FRAC_PI_2).cos()
}

pub fn ease_out_sine(t: f64) -> f64 {
    (t * std::f64::consts::FRAC_PI_2).sin()
}

pub fn ease_in_out_sine(t: f64) -> f64 {
    -((std::f64::consts::PI * t).cos() - 1.0) / 2.0
}

pub fn ease_in_expo(t: f64) -> f64 {
    if t == 0.0 {
        0.0
    } else {
        2.0_f64.powf(10.0 * t - 10.0)
    }
}

pub fn ease_out_expo(t: f64) -> f64 {
    if t == 1.0 {
        1.0
    } else {
        1.0 - 2.0_f64.powf(-10.0 * t)
    }
}

pub fn ease_in_out_expo(t: f64) -> f64 {
    if t == 0.0 {
        0.0
    } else if t == 1.0 {
        1.0
    } else if t < 0.5 {
        2.0_f64.powf(20.0 * t - 10.0) / 2.0
    } else {
        (2.0 - 2.0_f64.powf(-20.0 * t + 10.0)) / 2.0
    }
}

pub fn ease_in_circ(t: f64) -> f64 {
    1.0 - (1.0 - t * t).sqrt()
}

pub fn ease_out_circ(t: f64) -> f64 {
    (1.0 - (t - 1.0) * (t - 1.0)).sqrt()
}

pub fn ease_in_out_circ(t: f64) -> f64 {
    if t < 0.5 {
        (1.0 - (2.0 * t) * (2.0 * t)).sqrt() / -2.0 + 0.5
    } else {
        ((1.0 - (-2.0 * t + 2.0) * (-2.0 * t + 2.0)).sqrt() + 1.0) / 2.0
    }
}

const C1_BACK: f64 = 1.70158;
const C3_BACK: f64 = C1_BACK + 1.0;

pub fn ease_in_back(t: f64) -> f64 {
    C3_BACK * t * t * t - C1_BACK * t * t
}

pub fn ease_out_back(t: f64) -> f64 {
    let t1 = t - 1.0;
    1.0 + C3_BACK * t1 * t1 * t1 + C1_BACK * t1 * t1
}

pub fn ease_in_out_back(t: f64) -> f64 {
    let c2 = C1_BACK * 1.525;
    if t < 0.5 {
        ((2.0 * t) * (2.0 * t) * ((c2 + 1.0) * 2.0 * t - c2)) / 2.0
    } else {
        ((2.0 * t - 2.0) * (2.0 * t - 2.0) * ((c2 + 1.0) * (2.0 * t - 2.0) + c2) + 2.0) / 2.0
    }
}

const C4_ELASTIC: f64 = (2.0 * std::f64::consts::PI) / 3.0;

pub fn ease_in_elastic(t: f64) -> f64 {
    if t == 0.0 || t == 1.0 {
        t
    } else {
        -(2.0_f64.powf(10.0 * t - 10.0)) * ((t * 10.0 - 10.75) * C4_ELASTIC).sin()
    }
}

pub fn ease_out_elastic(t: f64) -> f64 {
    if t == 0.0 || t == 1.0 {
        t
    } else {
        2.0_f64.powf(-10.0 * t) * ((t * 10.0 - 0.75) * C4_ELASTIC).sin() + 1.0
    }
}

const C5_ELASTIC: f64 = (2.0 * std::f64::consts::PI) / 4.5;

pub fn ease_in_out_elastic(t: f64) -> f64 {
    if t == 0.0 || t == 1.0 {
        t
    } else if t < 0.5 {
        -(2.0_f64.powf(20.0 * t - 10.0) * ((20.0 * t - 11.125) * C5_ELASTIC).sin()) / 2.0
    } else {
        (2.0_f64.powf(-20.0 * t + 10.0) * ((20.0 * t - 11.125) * C5_ELASTIC).sin()) / 2.0 + 1.0
    }
}

pub fn ease_out_bounce(t: f64) -> f64 {
    const N1: f64 = 7.5625;
    const D1: f64 = 2.75;
    if t < 1.0 / D1 {
        N1 * t * t
    } else if t < 2.0 / D1 {
        let t1 = t - 1.5 / D1;
        N1 * t1 * t1 + 0.75
    } else if t < 2.5 / D1 {
        let t1 = t - 2.25 / D1;
        N1 * t1 * t1 + 0.9375
    } else {
        let t1 = t - 2.625 / D1;
        N1 * t1 * t1 + 0.984375
    }
}

pub fn ease_in_bounce(t: f64) -> f64 {
    1.0 - ease_out_bounce(1.0 - t)
}

pub fn ease_in_out_bounce(t: f64) -> f64 {
    if t < 0.5 {
        (1.0 - ease_out_bounce(1.0 - 2.0 * t)) / 2.0
    } else {
        (1.0 + ease_out_bounce(2.0 * t - 1.0)) / 2.0
    }
}

// ─── Spline evaluation ───────────────────────────────────────────────────────

/// Evaluate a cubic Bézier curve at parameter t.
/// p0, p1, p2, p3 are the control points.
pub fn bezier_cubic(p0: f64, p1: f64, p2: f64, p3: f64, t: f64) -> f64 {
    let t1 = 1.0 - t;
    t1 * t1 * t1 * p0 + 3.0 * t1 * t1 * t * p1 + 3.0 * t1 * t * t * p2 + t * t * t * p3
}

/// Evaluate a Catmull-Rom spline segment at parameter t.
pub fn catmull_rom(p0: f64, p1: f64, p2: f64, p3: f64, t: f64) -> f64 {
    let t2 = t * t;
    let t3 = t2 * t;
    0.5 * (2.0 * p1
        + (-p0 + p2) * t
        + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
        + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)
}

/// Cubic Hermite interpolation.
pub fn cubic_hermite(p0: f64, m0: f64, p1: f64, m1: f64, t: f64) -> f64 {
    let t2 = t * t;
    let t3 = t2 * t;
    let h00 = 2.0 * t3 - 3.0 * t2 + 1.0;
    let h10 = t3 - 2.0 * t2 + t;
    let h01 = -2.0 * t3 + 3.0 * t2;
    let h11 = t3 - t2;
    h00 * p0 + h10 * m0 + h01 * p1 + h11 * m1
}

// ─── Color conversions ───────────────────────────────────────────────────────

/// Convert RGB [0,1] to HSV. Returns (h: 0-360, s: 0-1, v: 0-1).
pub fn rgb_to_hsv(r: f64, g: f64, b: f64) -> (f64, f64, f64) {
    let max = r.max(g).max(b);
    let min = r.min(g).min(b);
    let delta = max - min;

    let h = if delta < f64::EPSILON {
        0.0
    } else if (max - r).abs() < f64::EPSILON {
        60.0 * (((g - b) / delta) % 6.0)
    } else if (max - g).abs() < f64::EPSILON {
        60.0 * (((b - r) / delta) + 2.0)
    } else {
        60.0 * (((r - g) / delta) + 4.0)
    };

    let h = if h < 0.0 { h + 360.0 } else { h };
    let s = if max < f64::EPSILON { 0.0 } else { delta / max };
    (h, s, max)
}

/// Convert HSV to RGB [0,1].
pub fn hsv_to_rgb(h: f64, s: f64, v: f64) -> (f64, f64, f64) {
    let c = v * s;
    let h_prime = (h / 60.0) % 6.0;
    let x = c * (1.0 - (h_prime % 2.0 - 1.0).abs());
    let m = v - c;

    let (r1, g1, b1) = match h_prime as u32 {
        0 => (c, x, 0.0),
        1 => (x, c, 0.0),
        2 => (0.0, c, x),
        3 => (0.0, x, c),
        4 => (x, 0.0, c),
        _ => (c, 0.0, x),
    };
    (r1 + m, g1 + m, b1 + m)
}

/// Convert RGB [0,1] to YUV (BT.601). Y: 0-1, U: -0.5-0.5, V: -0.5-0.5.
pub fn rgb_to_yuv(r: f64, g: f64, b: f64) -> (f64, f64, f64) {
    let y = 0.299 * r + 0.587 * g + 0.114 * b;
    let u = -0.14713 * r - 0.28886 * g + 0.436 * b;
    let v = 0.615 * r - 0.51499 * g - 0.10001 * b;
    (y, u, v)
}

/// Convert YUV to RGB [0,1].
pub fn yuv_to_rgb(y: f64, u: f64, v: f64) -> (f64, f64, f64) {
    let r = y + 1.13983 * v;
    let g = y - 0.39465 * u - 0.58060 * v;
    let b = y + 2.03211 * u;
    (r.clamp(0.0, 1.0), g.clamp(0.0, 1.0), b.clamp(0.0, 1.0))
}

/// Convert RGB [0,1] to CIE XYZ.
pub fn rgb_to_xyz(r: f64, g: f64, b: f64) -> (f64, f64, f64) {
    let linearize = |c: f64| -> f64 {
        if c > 0.04045 {
            ((c + 0.055) / 1.055).powf(2.4)
        } else {
            c / 12.92
        }
    };
    let r = linearize(r);
    let g = linearize(g);
    let b = linearize(b);

    let x = 0.4124564 * r + 0.3575761 * g + 0.1804375 * b;
    let y = 0.2126729 * r + 0.7151522 * g + 0.0721750 * b;
    let z = 0.0193339 * r + 0.1191920 * g + 0.9503041 * b;
    (x, y, z)
}

/// Convert CIE XYZ to LAB (D65 illuminant).
pub fn xyz_to_lab(x: f64, y: f64, z: f64) -> (f64, f64, f64) {
    let xn = 0.95047;
    let yn = 1.0;
    let zn = 1.08883;

    let f = |t: f64| -> f64 {
        if t > (6.0f64 / 29.0f64).powi(3) {
            t.cbrt()
        } else {
            t / (3.0 * (6.0f64 / 29.0f64).powi(2)) + 4.0 / 29.0
        }
    };

    let fx = f(x / xn);
    let fy = f(y / yn);
    let fz = f(z / zn);

    let l = 116.0 * fy - 16.0;
    let a = 500.0 * (fx - fy);
    let b_val = 200.0 * (fy - fz);
    (l, a, b_val)
}

/// Convert RGB [0,1] to LAB.
pub fn rgb_to_lab(r: f64, g: f64, b: f64) -> (f64, f64, f64) {
    let (x, y, z) = rgb_to_xyz(r, g, b);
    xyz_to_lab(x, y, z)
}

/// Convert CIE LAB to XYZ (D65 illuminant).
pub fn lab_to_xyz(l: f64, a: f64, b: f64) -> (f64, f64, f64) {
    let yn = 1.0;
    let xn = 0.95047;
    let zn = 1.08883;

    let fy = (l + 16.0) / 116.0;
    let fx = a / 500.0 + fy;
    let fz = fy - b / 200.0;

    let epsilon = (6.0f64 / 29.0f64).powi(3);
    let kappa = (29.0f64 / 6.0f64).powi(2) * 3.0;

    let xr = if fx.powi(3) > epsilon { fx.powi(3) } else { (116.0 * fx - 16.0) / kappa };
    let yr = if l > kappa * epsilon { ((l + 16.0) / 116.0).powi(3) } else { l / kappa };
    let zr = if fz.powi(3) > epsilon { fz.powi(3) } else { (116.0 * fz - 16.0) / kappa };

    (xr * xn, yr * yn, zr * zn)
}

/// Convert LAB to RGB [0,1].
pub fn lab_to_rgb(l: f64, a: f64, b: f64) -> (f64, f64, f64) {
    let (x, y, z) = lab_to_xyz(l, a, b);

    let r = 3.2404542 * x - 1.5371385 * y - 0.4985314 * z;
    let g = -0.9692660 * x + 1.8760108 * y + 0.0415560 * z;
    let b_val = 0.0556434 * x - 0.2040259 * y + 1.0572252 * z;

    let delinearize = |c: f64| -> f64 {
        if c > 0.0031308 {
            1.055 * c.powf(1.0 / 2.4) - 0.055
        } else {
            12.92 * c
        }
    };

    (
        delinearize(r).clamp(0.0, 1.0),
        delinearize(g).clamp(0.0, 1.0),
        delinearize(b_val).clamp(0.0, 1.0),
    )
}

// ─── Tone mapping ────────────────────────────────────────────────────────────

/// Reinhard tone mapping.
pub fn reinhard(hdr: f64) -> f64 {
    hdr / (1.0 + hdr)
}

/// ACES filmic tone mapping (approximation).
pub fn aces(x: f64) -> f64 {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    ((x * (a * x + b)) / (x * (c * x + d) + e)).clamp(0.0, 1.0)
}

/// Filmic tone mapping (Brooks style).
pub fn filmic(x: f64) -> f64 {
    let x = x.max(0.0);
    let a = 0.22;
    let b = 0.30;
    let c = 0.10;
    let d = 0.20;
    let e = 0.01;
    let f = 0.30;
    ((x * (a * x + c * b) + d * e) / (x * (a * x + b) + d * f)) - e / f
}

// ─── Kernel / sampling ───────────────────────────────────────────────────────

/// Generate a normalized Gaussian kernel of the given size and sigma.
pub fn gaussian_kernel(size: usize, sigma: f64) -> Vec<f64> {
    assert!(size % 2 == 1, "Kernel size must be odd");
    let half = size as i32 / 2;
    let mut kernel = Vec::with_capacity(size);
    let two_sigma_sq = 2.0 * sigma * sigma;
    let mut sum = 0.0;
    for i in -half..=half {
        let val = (-((i as f64) * (i as f64)) / two_sigma_sq).exp();
        kernel.push(val);
        sum += val;
    }
    for v in &mut kernel {
        *v /= sum;
    }
    kernel
}

/// Bilinear sample from a 2D buffer at fractional coordinates.
/// `data` is row-major RGBA (4 bytes per pixel), width and height in pixels.
pub fn bilinear_sample(data: &[u8], width: u32, height: u32, x: f64, y: f64) -> [u8; 4] {
    let x0 = (x.floor() as u32).min(width - 1);
    let y0 = (y.floor() as u32).min(height - 1);
    let x1 = (x0 + 1).min(width - 1);
    let y1 = (y0 + 1).min(height - 1);
    let fx = x - x.floor();
    let fy = y - y.floor();

    let pixel = |px: u32, py: u32| -> [f64; 4] {
        let idx = (py * width + px) as usize * 4;
        if idx + 3 < data.len() {
            [
                data[idx] as f64,
                data[idx + 1] as f64,
                data[idx + 2] as f64,
                data[idx + 3] as f64,
            ]
        } else {
            [0.0, 0.0, 0.0, 255.0]
        }
    };

    let p00 = pixel(x0, y0);
    let p10 = pixel(x1, y0);
    let p01 = pixel(x0, y1);
    let p11 = pixel(x1, y1);

    let result: [f64; 4] = std::array::from_fn(|i| {
        (p00[i] * (1.0 - fx) * (1.0 - fy)
            + p10[i] * fx * (1.0 - fy)
            + p01[i] * (1.0 - fx) * fy
            + p11[i] * fx * fy)
            .round()
            .clamp(0.0, 255.0)
    });

    [result[0] as u8, result[1] as u8, result[2] as u8, result[3] as u8]
}

// ─── Unit tests ──────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_lerp() {
        assert!((lerp(0.0, 10.0, 0.5) - 5.0).abs() < 1e-9);
        assert!((lerp(0.0, 10.0, 0.0)).abs() < 1e-9);
        assert!((lerp(0.0, 10.0, 1.0) - 10.0).abs() < 1e-9);
    }

    #[test]
    fn test_inverse_lerp() {
        assert!((inverse_lerp(0.0, 10.0, 5.0) - 0.5).abs() < 1e-9);
        assert!((inverse_lerp(0.0, 10.0, 0.0)).abs() < 1e-9);
        assert!((inverse_lerp(0.0, 10.0, 10.0) - 1.0).abs() < 1e-9);
    }

    #[test]
    fn test_clamp() {
        assert_eq!(clamp(5, 0, 10), 5);
        assert_eq!(clamp(-1, 0, 10), 0);
        assert_eq!(clamp(15, 0, 10), 10);
    }

    #[test]
    fn test_smoothstep() {
        assert!((smoothstep(0.0, 1.0, 0.5) - 0.5).abs() < 1e-9);
        assert!((smoothstep(0.0, 1.0, 0.0)).abs() < 1e-9);
        assert!((smoothstep(0.0, 1.0, 1.0) - 1.0).abs() < 1e-9);
    }

    #[test]
    fn test_smootherstep() {
        assert!((smootherstep(0.0, 1.0, 0.0)).abs() < 1e-9);
        assert!((smootherstep(0.0, 1.0, 1.0) - 1.0).abs() < 1e-9);
        assert!((smootherstep(0.0, 1.0, 0.5) - 0.5).abs() < 0.01);
    }

    #[test]
    fn test_vector2f_ops() {
        let a = Vector2f::new(1.0, 2.0);
        let b = Vector2f::new(3.0, 4.0);
        assert_eq!(a + b, Vector2f::new(4.0, 6.0));
        assert_eq!(b - a, Vector2f::new(2.0, 2.0));
        assert_eq!(a * 2.0, Vector2f::new(2.0, 4.0));
        assert_eq!(-a, Vector2f::new(-1.0, -2.0));
    }

    #[test]
    fn test_vector3f_cross() {
        let a = Vector3f::new(1.0, 0.0, 0.0);
        let b = Vector3f::new(0.0, 1.0, 0.0);
        let c = a.cross(b);
        assert!((c.x - 0.0).abs() < 1e-5);
        assert!((c.y - 0.0).abs() < 1e-5);
        assert!((c.z - 1.0).abs() < 1e-5);
    }

    #[test]
    fn test_vector4f_dot() {
        let a = Vector4f::new(1.0, 2.0, 3.0, 4.0);
        assert!((a.dot(a) - 30.0).abs() < 1e-5);
    }

    #[test]
    fn test_matrix3x3_identity_inverse() {
        let id = Matrix3x3::IDENTITY;
        let inv = id.inverse().unwrap();
        assert_eq!(inv, id);
    }

    #[test]
    fn test_matrix4x4_determinant() {
        let id = Matrix4x4::IDENTITY;
        assert!((id.determinant() - 1.0).abs() < 1e-5);
    }

    #[test]
    fn test_matrix4x4_inverse() {
        let m = Matrix4x4::translation(5.0, 3.0, 1.0);
        let inv = m.inverse().unwrap();
        let result = m.multiply(&inv);
        for i in 0..4 {
            for j in 0..4 {
                let expected = if i == j { 1.0 } else { 0.0 };
                assert!((result.m[i][j] - expected).abs() < 1e-4, "m[{i}][{j}]");
            }
        }
    }

    #[test]
    fn test_easing_quad() {
        assert!((ease_in_quad(0.5) - 0.25).abs() < 1e-9);
        assert!((ease_out_quad(0.5) - 0.75).abs() < 1e-9);
    }

    #[test]
    fn test_easing_cubic() {
        assert!((ease_in_cubic(0.5) - 0.125).abs() < 1e-9);
        assert!((ease_out_cubic(0.5) - 0.875).abs() < 1e-9);
    }

    #[test]
    fn test_easing_sine() {
        assert!((ease_in_sine(0.0)).abs() < 1e-9);
        assert!((ease_out_sine(1.0) - 1.0).abs() < 1e-9);
    }

    #[test]
    fn test_bezier_cubic() {
        assert!((bezier_cubic(0.0, 0.0, 1.0, 1.0, 0.0)).abs() < 1e-9);
        assert!((bezier_cubic(0.0, 0.0, 1.0, 1.0, 1.0) - 1.0).abs() < 1e-9);
    }

    #[test]
    fn test_catmull_rom() {
        let val = catmull_rom(0.0, 0.0, 1.0, 1.0, 0.5);
        assert!(val > 0.0 && val < 1.0, "Catmull-Rom at 0.5 should be between 0 and 1");
    }

    #[test]
    fn test_rgb_hsv_roundtrip() {
        let (h, s, v) = rgb_to_hsv(0.5, 0.2, 0.8);
        let (r, g, b) = hsv_to_rgb(h, s, v);
        assert!((r - 0.5).abs() < 1e-6, "R mismatch");
        assert!((g - 0.2).abs() < 1e-6, "G mismatch");
        assert!((b - 0.8).abs() < 1e-6, "B mismatch");
    }

    #[test]
    fn test_rgb_yuv_roundtrip() {
        let (y, u, v) = rgb_to_yuv(0.5, 0.3, 0.7);
        let (r, g, b) = yuv_to_rgb(y, u, v);
        assert!((r - 0.5).abs() < 1e-4, "R mismatch");
        assert!((g - 0.3).abs() < 1e-4, "G mismatch");
        assert!((b - 0.7).abs() < 1e-4, "B mismatch");
    }

    #[test]
    fn test_rgb_lab_roundtrip() {
        let (l, a, b) = rgb_to_lab(0.5, 0.3, 0.7);
        let (r, g, bv) = lab_to_rgb(l, a, b);
        assert!((r - 0.5).abs() < 1e-3, "R mismatch");
        assert!((g - 0.3).abs() < 1e-3, "G mismatch");
        assert!((bv - 0.7).abs() < 1e-3, "B mismatch");
    }

    #[test]
    fn test_reinhard() {
        assert!((reinhard(0.0)).abs() < 1e-9);
        assert!((reinhard(1.0) - 0.5).abs() < 1e-9);
    }

    #[test]
    fn test_aces() {
        assert!((aces(0.0)).abs() < 1e-4);
        assert!(aces(1.0) > 0.0 && aces(1.0) <= 1.0);
    }

    #[test]
    fn test_gaussian_kernel() {
        let kernel = gaussian_kernel(5, 1.0);
        assert_eq!(kernel.len(), 5);
        let sum: f64 = kernel.iter().sum();
        assert!((sum - 1.0).abs() < 1e-9, "Kernel must sum to 1");
    }

    #[test]
    fn test_bilinear_sample() {
        let mut data = vec![0u8; 4 * 4]; // 2x2 image
        data[0] = 255; data[1] = 0; data[2] = 0; data[3] = 255;   // red
        data[4] = 0; data[5] = 255; data[6] = 0; data[7] = 255;   // green
        data[8] = 0; data[9] = 0; data[10] = 255; data[11] = 255; // blue
        data[12] = 255; data[13] = 255; data[14] = 0; data[15] = 255; // yellow
        let result = bilinear_sample(&data, 2, 2, 0.0, 0.0);
        assert_eq!(result[0], 255); // top-left pixel is red
        assert_eq!(result[1], 0);
    }

    #[test]
    fn test_easing_bounce_boundary() {
        assert!((ease_in_bounce(0.0)).abs() < 1e-9);
        assert!((ease_out_bounce(1.0) - 1.0).abs() < 1e-9);
    }
}
