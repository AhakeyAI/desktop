// Research fixture only: no microphone, installation, application settings or keyboard writes.
// Build alongside Sources/Utilities/SpeechTranscriptSnapshot.swift with Xcode26+.
import Foundation
import Speech
import AVFoundation
@main struct Replay {
 static func main() async {
  guard #available(macOS 26.0, *), CommandLine.arguments.count > 1 else { return }
  guard SpeechTranscriber.isAvailable else { return }
  let module = SpeechTranscriber(locale:Locale(identifier:"zh_CN"),transcriptionOptions:[],reportingOptions:CommandLine.arguments.contains("--fast") ? [.volatileResults,.fastResults] : [.volatileResults],attributeOptions:[.audioTimeRange])
  let analyzer = SpeechAnalyzer(modules:[module])
  let started = Date()
  let reader = Task { () throws -> [String:Any] in
   var accumulator = SpeechTranscriptAccumulator()
   var finals = 0, volatile = 0, events:[[String:Any]] = []
   for try await result in module.results {
    let text = String(result.text.characters)
    let span = SpeechTranscriptAccumulator.AudioSpan(start:result.range.start.seconds,duration:result.range.duration.seconds)
    let completion = result.isFinal ? span.map { SpeechTranscriptAccumulator.Completion(audio:$0) } : nil
    let preview = accumulator.apply(text,completion:completion)
    if result.isFinal { finals += 1 } else { volatile += 1 }
    events.append(["elapsed":Date().timeIntervalSince(started),"segmentFinal":result.isFinal,"text":text,"preview":preview])
   }
   var value: String, needsReview = false
   switch accumulator.finalization {
   case .ready(let text):value = text
   case .review(_,let latest):value=latest;needsReview=true
   case .empty:value=""
   }
   return ["text":value,"needsReview":needsReview,"finalizedSegments":finals,"volatileUpdates":volatile,"events":events,
    "literalLinebreakWordCount":value.components(separatedBy:"换行").count-1,"lineBreakCount":value.filter{$0 == "\n"}.count,"intentionalRepeatCount":value.components(separatedBy:"确认").count-1,"containsPrefix":value.contains("今天测试"),"containsSuffix":value.contains("内容都保留")]
  }
  var report:[String:Any]=["microphoneOpened":false,"inputKind":"callerProvidedAudioFile","assetInstallRequested":false]
  do {
   guard let desired = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith:[module]) else { throw NSError(domain:"Probe",code:1) }
   let file=try AVAudioFile(forReading:URL(fileURLWithPath:CommandLine.arguments[1]), commonFormat:desired.commonFormat, interleaved:desired.isInterleaved)
   guard file.processingFormat.sampleRate == desired.sampleRate,
         file.processingFormat.channelCount == desired.channelCount,
         Double(file.length) / file.processingFormat.sampleRate <= 60 else {
       throw NSError(domain:"Speech26Fixture",code:2,userInfo:[NSLocalizedDescriptionKey:"Use a normalized mono16kHz fixture of at most60 seconds"])
   }
   try await analyzer.prepareToAnalyze(in:file.processingFormat)
   report["prepareCompletedSeconds"] = Date().timeIntervalSince(started)
   let input = AsyncStream<AnalyzerInput>.makeStream()
   let analysis = Task { try await analyzer.start(inputSequence:input.stream) }
   let chunkFrames = AVAudioFrameCount(max(1, Int(desired.sampleRate / 10)))
   report["firstInputSeconds"] = Date().timeIntervalSince(started)
   while file.framePosition < file.length {
    let buffer=AVAudioPCMBuffer(pcmFormat:file.processingFormat,frameCapacity:chunkFrames)!
    try file.read(into:buffer,frameCount:chunkFrames)
    input.continuation.yield(AnalyzerInput(buffer:buffer))
    try await Task.sleep(for:.milliseconds(100))
   }
   report["inputFinishedSeconds"] = Date().timeIntervalSince(started)
   input.continuation.finish()
   try await analysis.value
   try await analyzer.finalizeAndFinishThroughEndOfInput()
   report["finalizedSeconds"] = Date().timeIntervalSince(started)
   report.merge(try await reader.value){_,new in new};report["success"]=true
  } catch {
   await analyzer.cancelAndFinishNow();reader.cancel();report["success"]=false;report["error"]=String(describing:error)
  }
  print(String(decoding:try!JSONSerialization.data(withJSONObject:report,options:[.sortedKeys]),as:UTF8.self))
 }
}
