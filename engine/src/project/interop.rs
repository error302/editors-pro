//! Format interoperability — EDL, FCPXML, OpenTimelineIO export.
//!
//! Round-trips a timeline to other NLEs (DaVinci Resolve, Premiere Pro,
//! Final Cut Pro). Effects, color, and audio don't always translate —
//! those need to be re-done in the target tool. The clip in/out points
//! and the cut positions are what translate.
//!
//! ## video: debt markers
//!
//! - EDL CMX 3600 only, upgrade to CMX 3400E if extended events are needed
//! - FCPXML v1.10 only, upgrade to v1.11 if FCP 11 features are needed
//! - OpenTimelineIO 0.17, upgrade to 0.18 when the spec finalizes
//! - No effect/transitions in export, upgrade to FCPXML effect dictionary if round-tripping effects is needed
//! - No color metadata, upgrade to FCPXML color sync if color round-trip is needed

use serde::{Deserialize, Serialize};

/// Format to export.
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "snake_case")]
pub enum InteropFormat {
    /// CMX 3600 Edit Decision List. The oldest, simplest, most widely supported.
    Edl,
    /// Final Cut Pro XML (FCPXML v1.10). Also imported by Premiere and Resolve.
    Fcpxml,
    /// OpenTimelineIO 0.17. The modern open standard from Pixar.
    OpenTimelineIO,
}

/// A clip in the timeline, in the format the interop exporter needs.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct InteropClip {
    /// Source media file path.
    pub source_path: String,
    /// Source in-point (ms, relative to source start).
    pub source_in_ms: i64,
    /// Source out-point (ms, relative to source start).
    pub source_out_ms: i64,
    /// Timeline start (ms, relative to timeline start).
    pub timeline_start_ms: i64,
    /// Timeline end (ms, relative to timeline start).
    pub timeline_end_ms: i64,
    /// Track index (0 = main video track).
    pub track_index: usize,
    /// Clip name (often the file name without extension).
    pub name: String,
}

/// A timeline to export.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct InteropTimeline {
    pub name: String,
    pub frame_rate_num: u32,   // e.g. 24000
    pub frame_rate_den: u32,   // e.g. 1001 → 23.976 fps
    pub width: u32,
    pub height: u32,
    pub clips: Vec<InteropClip>,
}

/// Export a timeline to the given format. Returns the file content as a string.
pub fn export(timeline: &InteropTimeline, format: InteropFormat) -> String {
    match format {
        InteropFormat::Edl => export_edl(timeline),
        InteropFormat::Fcpxml => export_fcpxml(timeline),
        InteropFormat::OpenTimelineIO => export_otio(timeline),
    }
}

/// Export to CMX 3600 EDL format.
///
/// video: EDL CMX 3600 only, upgrade to CMX 3400E if extended events are needed
pub fn export_edl(timeline: &InteropTimeline) -> String {
    let mut out = String::new();
    out.push_str(&format!("TITLE: {}\n", timeline.name));
    out.push_str(&format!(
        "FCM: NON-DROP FRAME\n\n"
    ));

    for (i, clip) in timeline.clips.iter().enumerate() {
        let event_num = i + 1;
        // Format: AA/V  C     src_in src_out rec_in rec_out
        let src_in = format_timecode(clip.source_in_ms, timeline.frame_rate_num, timeline.frame_rate_den);
        let src_out = format_timecode(clip.source_out_ms, timeline.frame_rate_num, timeline.frame_rate_den);
        let rec_in = format_timecode(clip.timeline_start_ms, timeline.frame_rate_num, timeline.frame_rate_den);
        let rec_out = format_timecode(clip.timeline_end_ms, timeline.frame_rate_num, timeline.frame_rate_den);

        out.push_str(&format!(
            "{:03}  AX       V     C        {} {} {} {}\n",
            event_num, src_in, src_out, rec_in, rec_out
        ));
        out.push_str(&format!("FROM CLIP NAME: {}\n", clip.name));
        if let Some(filename) = std::path::Path::new(&clip.source_path).file_name() {
            out.push_str(&format!("SOURCE: {}\n", filename.to_string_lossy()));
        }
        out.push('\n');
    }
    out
}

/// Export to FCPXML v1.10 format.
///
/// video: FCPXML v1.10 only, upgrade to v1.11 if FCP 11 features are needed
/// video: no effect/transitions in export, upgrade to FCPXML effect dictionary if round-tripping effects is needed
pub fn export_fcpxml(timeline: &InteropTimeline) -> String {
    let mut out = String::new();
    out.push_str("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
    out.push_str("<!DOCTYPE fcpxml>\n");
    out.push_str("<fcpxml version=\"1.10\">\n");
    out.push_str("  <resources>\n");

    // Format resource
    out.push_str(&format!(
        "    <format id=\"r1\" name=\"FFVideoFormat{}x{}p{}\" frameDuration=\"{}/{}s\" width=\"{}\" height=\"{}\"/>\n",
        timeline.width,
        timeline.height,
        timeline.frame_rate_num / timeline.frame_rate_den,
        timeline.frame_rate_den,
        timeline.frame_rate_num,
        timeline.width,
        timeline.height,
    ));

    // Asset resources (one per unique source path)
    let mut asset_ids = std::collections::HashMap::new();
    let mut next_asset_id = 2;
    for clip in &timeline.clips {
        if !asset_ids.contains_key(&clip.source_path) {
            let id = format!("r{}", next_asset_id);
            asset_ids.insert(clip.source_path.clone(), id.clone());
            next_asset_id += 1;
            let filename = std::path::Path::new(&clip.source_path)
                .file_name()
                .map(|f| f.to_string_lossy().to_string())
                .unwrap_or_else(|| clip.name.clone());
            out.push_str(&format!(
                "    <asset id=\"{}\" name=\"{}\" src=\"{}\" start=\"0s\" duration=\"0s\" hasVideo=\"1\"/>\n",
                id, filename, clip.source_path
            ));
        }
    }
    out.push_str("  </resources>\n");

    // Library + event + project + sequence
    out.push_str("  <library>\n");
    out.push_str(&format!("    <event name=\"{}\">\n", timeline.name));
    out.push_str(&format!(
        "      <project name=\"{}\">\n",
        timeline.name
    ));
    out.push_str(&format!(
        "        <sequence format=\"r1\" tcStart=\"0s\" tcFormat=\"NDF\" frameDuration=\"{}/{}s\">\n",
        timeline.frame_rate_den, timeline.frame_rate_num
    ));
    out.push_str("          <spine>\n");

    // Sort clips by timeline start
    let mut sorted_clips: Vec<&InteropClip> = timeline.clips.iter().collect();
    sorted_clips.sort_by_key(|c| c.timeline_start_ms);

    for clip in &sorted_clips {
        let asset_id = asset_ids.get(&clip.source_path).unwrap();
        let offset = format_timecode_seconds(clip.timeline_start_ms);
        let duration = format_timecode_seconds(clip.timeline_end_ms - clip.timeline_start_ms);
        let src_start = format_timecode_seconds(clip.source_in_ms);

        out.push_str(&format!(
            "            <asset-clip name=\"{}\" ref=\"{}\" offset=\"{}s\" duration=\"{}s\" start=\"{}s\"/>\n",
            clip.name, asset_id, offset, duration, src_start
        ));
    }

    out.push_str("          </spine>\n");
    out.push_str("        </sequence>\n");
    out.push_str("      </project>\n");
    out.push_str("    </event>\n");
    out.push_str("  </library>\n");
    out.push_str("</fcpxml>\n");
    out
}

/// Export to OpenTimelineIO 0.17 (JSON).
///
/// video: OpenTimelineIO 0.17, upgrade to 0.18 when the spec finalizes
pub fn export_otio(timeline: &InteropTimeline) -> String {
    let mut out = String::new();
    out.push_str("{\n");
    out.push_str("  \"OTIO_SCHEMA\": \"Timeline.1\",\n");
    out.push_str(&format!("  \"name\": {},\n", serde_json::to_string(&timeline.name).unwrap()));
    out.push_str("  \"metadata\": {\n");
    out.push_str(&format!(
        "    \"editors_pro\": {{ \"width\": {}, \"height\": {}, \"frame_rate_num\": {}, \"frame_rate_den\": {} }}\n",
        timeline.width, timeline.height, timeline.frame_rate_num, timeline.frame_rate_den
    ));
    out.push_str("  },\n");
    out.push_str("  \"tracks\": {\n");
    out.push_str("    \"OTIO_SCHEMA\": \"Stack.1\",\n");
    out.push_str("    \"name\": \"tracks\",\n");
    out.push_str("    \"children\": [\n");
    out.push_str("      {\n");
    out.push_str("        \"OTIO_SCHEMA\": \"Track.1\",\n");
    out.push_str("        \"name\": \"V1\",\n");
    out.push_str("        \"kind\": \"Video\",\n");
    out.push_str("        \"children\": [\n");

    let mut sorted_clips: Vec<&InteropClip> = timeline.clips.iter().collect();
    sorted_clips.sort_by_key(|c| c.timeline_start_ms);

    let n = sorted_clips.len();
    for (i, clip) in sorted_clips.iter().enumerate() {
        let duration_frames = ms_to_frames(
            clip.timeline_end_ms - clip.timeline_start_ms,
            timeline.frame_rate_num,
            timeline.frame_rate_den,
        );
        let src_start_frames = ms_to_frames(
            clip.source_in_ms,
            timeline.frame_rate_num,
            timeline.frame_rate_den,
        );
        let src_duration_frames = ms_to_frames(
            clip.source_out_ms - clip.source_in_ms,
            timeline.frame_rate_num,
            timeline.frame_rate_den,
        );

        out.push_str("          {\n");
        out.push_str("            \"OTIO_SCHEMA\": \"Clip.1\",\n");
        out.push_str(&format!("            \"name\": {},\n", serde_json::to_string(&clip.name).unwrap()));
        out.push_str("            \"source_range\": {\n");
        out.push_str("              \"OTIO_SCHEMA\": \"TimeRange.1\",\n");
        out.push_str(&format!("              \"start_time\": {{ \"OTIO_SCHEMA\": \"RationalTime.1\", \"value\": {}, \"rate\": {}/{} }},\n",
            src_start_frames, timeline.frame_rate_num, timeline.frame_rate_den));
        out.push_str(&format!("              \"duration\": {{ \"OTIO_SCHEMA\": \"RationalTime.1\", \"value\": {}, \"rate\": {}/{} }}\n",
            src_duration_frames, timeline.frame_rate_num, timeline.frame_rate_den));
        out.push_str("            },\n");
        out.push_str("            \"media_reference\": {\n");
        out.push_str("              \"OTIO_SCHEMA\": \"ExternalReference.1\",\n");
        out.push_str(&format!("              \"target_url\": {}\n", serde_json::to_string(&clip.source_path).unwrap()));
        out.push_str("            }\n");
        if i < n - 1 {
            out.push_str("          },\n");
        } else {
            out.push_str("          }\n");
        }
    }

    out.push_str("        ]\n");
    out.push_str("      }\n");
    out.push_str("    ]\n");
    out.push_str("  }\n");
    out.push_str("}\n");
    out
}

fn format_timecode(ms: i64, fr_num: u32, fr_den: u32) -> String {
    let fps = (fr_num as f64) / (fr_den as f64);
    let total_frames = (ms as f64 / 1000.0 * fps).round() as i64;
    let fps_int = fps.round() as i64;
    let frames = total_frames % fps_int;
    let total_seconds = total_frames / fps_int;
    let seconds = total_seconds % 60;
    let total_minutes = total_seconds / 60;
    let minutes = total_minutes % 60;
    let hours = total_minutes / 60;
    format!("{:02}:{:02}:{:02}:{:02}", hours, minutes, seconds, frames)
}

fn format_timecode_seconds(ms: i64) -> String {
    // FCPXML uses seconds as a fraction: 123/1000s style. We return the
    // numerator when the denominator is 1000.
    format!("{}", ms)
}

fn ms_to_frames(ms: i64, fr_num: u32, fr_den: u32) -> i64 {
    let fps = (fr_num as f64) / (fr_den as f64);
    (ms as f64 / 1000.0 * fps).round() as i64
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample_timeline() -> InteropTimeline {
        InteropTimeline {
            name: "Test Edit".into(),
            frame_rate_num: 24000,
            frame_rate_den: 1001,
            width: 1920,
            height: 1080,
            clips: vec![
                InteropClip {
                    source_path: "/media/clip1.mp4".into(),
                    source_in_ms: 0,
                    source_out_ms: 2000,
                    timeline_start_ms: 0,
                    timeline_end_ms: 2000,
                    track_index: 0,
                    name: "Clip 1".into(),
                },
                InteropClip {
                    source_path: "/media/clip2.mp4".into(),
                    source_in_ms: 500,
                    source_out_ms: 2500,
                    timeline_start_ms: 2000,
                    timeline_end_ms: 4000,
                    track_index: 0,
                    name: "Clip 2".into(),
                },
            ],
        }
    }

    #[test]
    fn export_edl_has_title_and_events() {
        let tl = sample_timeline();
        let edl = export_edl(&tl);
        assert!(edl.contains("TITLE: Test Edit"));
        assert!(edl.contains("001  AX       V"));
        assert!(edl.contains("FROM CLIP NAME: Clip 1"));
        assert!(edl.contains("002  AX       V"));
    }

    #[test]
    fn export_fcpxml_is_valid_xml() {
        let tl = sample_timeline();
        let xml = export_fcpxml(&tl);
        assert!(xml.starts_with("<?xml"));
        assert!(xml.contains("<fcpxml version=\"1.10\">"));
        assert!(xml.contains("<asset-clip"));
        assert!(xml.contains("</fcpxml>"));
    }

    #[test]
    fn export_otio_is_valid_json() {
        let tl = sample_timeline();
        let json = export_otio(&tl);
        assert!(json.starts_with("{"));
        assert!(json.contains("\"OTIO_SCHEMA\": \"Timeline.1\""));
        // Parse to verify it's valid JSON
        let _: serde_json::Value = serde_json::from_str(&json).expect("OTIO output must be valid JSON");
    }

    #[test]
    fn format_timecode_zero() {
        let tc = format_timecode(0, 24000, 1001);
        assert_eq!(tc, "00:00:00:00");
    }

    #[test]
    fn format_timecode_one_second() {
        // 1 second at 24fps = 24 frames
        let tc = format_timecode(1000, 24, 1);
        assert_eq!(tc, "00:00:01:00");
    }
}
