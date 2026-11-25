import AVFoundation
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let pcmPlayer = PcmAudioStreamPlayer()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let channel = FlutterMethodChannel(
      name: "piano_exercises/pcm_audio",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "enqueue":
        guard let args = call.arguments as? [String: Any],
              let typedData = args["pcm"] as? FlutterStandardTypedData else {
          result(nil)
          return
        }
        let sampleRate = (args["sampleRate"] as? NSNumber)?.intValue ?? 24000
        let data = typedData.data
        guard (8000...96000).contains(sampleRate),
              data.count >= 2,
              data.count % 2 == 0,
              data.count <= 262_144 else {
          result(nil)
          return
        }
        self?.pcmPlayer.enqueue(pcm16Data: data, sampleRate: sampleRate)
        result(nil)
      case "stop":
        self?.pcmPlayer.stop()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}

private final class PcmAudioStreamPlayer {
  private static let maxPendingBuffers = 12
  private let queue = DispatchQueue(label: "piano_exercises.pcm_audio")
  private var engine: AVAudioEngine?
  private var playerNode: AVAudioPlayerNode?
  private var audioFormat: AVAudioFormat?
  private var activeSampleRate: Int = 0
  private var pendingBuffers: Int = 0
  private var generation: UInt64 = 0

  func enqueue(pcm16Data: Data, sampleRate: Int) {
    let frameCount = pcm16Data.count / 2
    guard frameCount > 0 else { return }
    queue.async { [weak self] in
      guard let self = self,
            self.pendingBuffers < Self.maxPendingBuffers,
            let (engine, node, format) = self.ensurePipeline(sampleRate: sampleRate),
            let buffer = AVAudioPCMBuffer(
              pcmFormat: format,
              frameCapacity: AVAudioFrameCount(frameCount)
            ),
            let channelData = buffer.floatChannelData?[0] else {
        return
      }
      buffer.frameLength = AVAudioFrameCount(frameCount)
      pcm16Data.withUnsafeBytes { rawBuffer in
        guard let bytes = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
          return
        }
        let scale: Float = 1.0 / 32768.0
        for i in 0..<frameCount {
          let lo = UInt16(bytes[i * 2])
          let hi = UInt16(bytes[i * 2 + 1]) << 8
          let sample = Int16(bitPattern: lo | hi)
          channelData[i] = Float(sample) * scale
        }
      }
      if !engine.isRunning {
        do {
          try engine.start()
        } catch {
          return
        }
      }
      guard engine.isRunning else { return }

      let scheduledGen = self.generation
      self.pendingBuffers += 1
      node.scheduleBuffer(buffer) { [weak self] in
        self?.queue.async {
          guard let self = self, self.generation == scheduledGen else { return }
          self.pendingBuffers = max(0, self.pendingBuffers - 1)
        }
      }
      if !node.isPlaying {
        node.play()
      }
    }
  }

  func stop() {
    queue.async { [weak self] in
      guard let self = self else { return }
      self.generation &+= 1
      self.pendingBuffers = 0
      self.playerNode?.stop()
    }
  }

  private func ensurePipeline(
    sampleRate: Int
  ) -> (AVAudioEngine, AVAudioPlayerNode, AVAudioFormat)? {
    if let engine = engine,
       let node = playerNode,
       let format = audioFormat,
       activeSampleRate == sampleRate {
      return (engine, node, format)
    }
    playerNode?.stop()
    engine?.stop()
    pendingBuffers = 0

    let session = AVAudioSession.sharedInstance()
    try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
    try? session.setActive(true)

    guard let format = AVAudioFormat(
      standardFormatWithSampleRate: Double(sampleRate),
      channels: 1
    ) else {
      return nil
    }
    let newEngine = AVAudioEngine()
    let newNode = AVAudioPlayerNode()
    newEngine.attach(newNode)
    newEngine.connect(newNode, to: newEngine.mainMixerNode, format: format)
    do {
      try newEngine.start()
    } catch {
      return nil
    }

    engine = newEngine
    playerNode = newNode
    audioFormat = format
    activeSampleRate = sampleRate
    return (newEngine, newNode, format)
  }
}
