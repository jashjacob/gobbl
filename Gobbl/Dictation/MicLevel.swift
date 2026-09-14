/// The microphone level (0…1) while dictating, read by the pet's waveform
/// every frame. A plain value on purpose: written on the main thread by
/// `Dictation`, read on the main thread by `GobView`'s Canvas.
enum MicLevel {
    nonisolated(unsafe) static var value: Float = 0
}
