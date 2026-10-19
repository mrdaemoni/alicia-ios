#if DEBUG
import Foundation

/// Her real speaking rhythm for the Motion Lab: the word start and end times of
/// the first 36.3 s of a 2026-10-16 live shakedown of her voice (Gemini Leda,
/// aligned by local Whisper). Times only. No words, no text, nothing private.
/// It loops, so the lab can watch phrases and the pauses between them.
enum OrganicVoiceFixture {
    static let loopSeconds = 36.6
    static let words: [(Double, Double)] = [
        (0.920, 1.600),
        (1.600, 1.940),
        (1.940, 2.340),
        (2.960, 3.300),
        (3.660, 4.140),
        (6.380, 6.500),
        (6.500, 6.840),
        (6.980, 7.260),
        (8.120, 8.280),
        (8.280, 8.560),
        (8.560, 8.880),
        (8.880, 9.420),
        (9.420, 9.700),
        (9.700, 9.920),
        (9.920, 10.360),
        (10.900, 11.020),
        (11.020, 11.640),
        (11.640, 12.020),
        (12.020, 12.360),
        (13.080, 13.320),
        (13.320, 13.540),
        (13.540, 13.840),
        (13.840, 14.140),
        (14.140, 14.500),
        (14.500, 15.280),
        (15.280, 15.660),
        (16.010, 16.550),
        (16.550, 17.010),
        (17.010, 17.230),
        (17.230, 17.730),
        (17.730, 18.030),
        (18.030, 18.790),
        (20.010, 20.070),
        (20.070, 20.410),
        (20.410, 20.610),
        (20.610, 21.110),
        (21.850, 22.270),
        (22.270, 22.470),
        (22.470, 23.070),
        (23.070, 23.430),
        (23.430, 23.590),
        (23.590, 23.830),
        (23.830, 24.190),
        (24.790, 24.870),
        (24.870, 25.110),
        (25.110, 25.310),
        (25.310, 25.530),
        (25.530, 25.730),
        (25.730, 26.290),
        (26.290, 26.750),
        (26.750, 26.970),
        (26.970, 27.370),
        (28.350, 29.070),
        (29.330, 29.870),
        (30.270, 30.830),
        (31.310, 31.390),
        (31.390, 31.510),
        (31.510, 31.650),
        (31.650, 31.890),
        (31.890, 32.450),
        (33.190, 33.470),
        (34.110, 34.210),
        (34.210, 34.490),
        (34.490, 34.690),
        (34.690, 35.090),
        (35.790, 35.970)
    ]

    /// The same rhythm repeated `loops` times on one clock, sorted by start.
    static func cues(loops: Int = 40) -> [OrganicVoice.Cue] {
        (0..<loops).flatMap { loop in
            words.map { OrganicVoice.Cue(start: $0.0 + Double(loop) * loopSeconds, end: $0.1 + Double(loop) * loopSeconds) }
        }
    }
}
#endif
