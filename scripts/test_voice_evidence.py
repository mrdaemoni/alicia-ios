#!/usr/bin/env python3
"""Run the actual iOS audio/archive source against generated PCM and fake transport.

Creates a temporary XCTest target; never changes the app project or starts its live
service. All test audio and metadata live in temporary directories on the simulator.
"""
from pathlib import Path
import json, os, plistlib, shutil, subprocess, tempfile
import xml.etree.ElementTree as ET
root=Path(__file__).resolve().parents[1]
work=Path(tempfile.mkdtemp(prefix='alicia-voice-tests-'))
project=work/'Alicia.xcodeproj';shutil.copytree(root/'Alicia.xcodeproj',project)
for name in ['Alicia','AliciaWidgets']:(work/name).symlink_to(root/name,target_is_directory=True)
for source in root.glob('*.plist'):(work/source.name).symlink_to(source)
p=json.loads(subprocess.check_output(['plutil','-convert','json','-o','-',str(project/'project.pbxproj')]))
o=p['objects'];r=o[p['rootObject']]
def add(n,value):
 key='CD00000000000000000000'+n;o[key]=value;return key
ref=add('01',dict(isa='PBXFileReference',explicitFileType='wrapper.cfbundle',path='VoiceEvidenceTests.xctest',sourceTree='BUILT_PRODUCTS_DIR'))
group=add('02',dict(isa='PBXFileSystemSynchronizedRootGroup',explicitFileTypes={},explicitFolders=[],path='VoiceEvidenceTests',sourceTree='<group>'))
sources=add('03',dict(isa='PBXSourcesBuildPhase',buildActionMask='2147483647',files=[],runOnlyForDeploymentPostprocessing='0'))
frameworks=add('04',dict(isa='PBXFrameworksBuildPhase',buildActionMask='2147483647',files=[],runOnlyForDeploymentPostprocessing='0'))
configs=[]
for i,name in enumerate(['Debug','Release']):
 configs.append(add('0'+str(5+i),dict(isa='XCBuildConfiguration',name=name,buildSettings=dict(CODE_SIGN_STYLE='Automatic',GENERATE_INFOPLIST_FILE='YES',IPHONEOS_DEPLOYMENT_TARGET='17.0',PRODUCT_BUNDLE_IDENTIFIER='com.myalicia.voiceevidencetests',PRODUCT_NAME='$(TARGET_NAME)',SWIFT_VERSION='5.0',TARGETED_DEVICE_FAMILY='1,2',SDKROOT='iphoneos'))))
cl=add('07',dict(isa='XCConfigurationList',buildConfigurations=configs,defaultConfigurationIsVisible='0',defaultConfigurationName='Release'))
target=add('10',dict(isa='PBXNativeTarget',name='VoiceEvidenceTests',productName='VoiceEvidenceTests',productType='com.apple.product-type.bundle.unit-test',productReference=ref,buildConfigurationList=cl,buildPhases=[sources,frameworks],buildRules=[],dependencies=[],fileSystemSynchronizedGroups=[group]))
r['targets'].append(target);o[r['mainGroup']]['children'].append(group);o[r['productRefGroup']]['children'].append(ref)
(project/'project.pbxproj').write_bytes(plistlib.dumps(p))
scheme=project/'xcshareddata/xcschemes/Alicia.xcscheme';tree=ET.parse(scheme)
attrs=dict(BuildableIdentifier='primary',BlueprintIdentifier=target,BuildableName='VoiceEvidenceTests.xctest',BlueprintName='VoiceEvidenceTests',ReferencedContainer='container:Alicia.xcodeproj')
entry=ET.SubElement(tree.find('.//BuildActionEntries'),'BuildActionEntry',dict(buildForTesting='YES',buildForRunning='NO',buildForProfiling='NO',buildForArchiving='NO',buildForAnalyzing='NO'))
ET.SubElement(entry,'BuildableReference',attrs)
test=ET.SubElement(tree.find('.//Testables'),'TestableReference',dict(skipped='NO'));ET.SubElement(test,'BuildableReference',attrs)
tree.write(scheme,encoding='utf-8',xml_declaration=True)
folder=work/'VoiceEvidenceTests';folder.mkdir()
(folder/'VoiceEvidence.swift').symlink_to(root/'Alicia/Core/VoiceEvidence.swift')
(folder/'VoiceEvidenceTests.swift').write_text(r'''
import XCTest
import Foundation
import AVFoundation
import CryptoKit
protocol AliciaService {
 func voiceAction(_ body:[String:Any]) async -> VoiceEvidenceResult?
 func voiceRecordings(recordingID:String) async -> VoiceEvidencePayload?
 func uploadVoice(recordingID:String,segment:VoiceSegment,file:URL) async -> VoiceEvidenceResult?
 func downloadVoice(recordingID:String,segmentID:String) async -> Data?
}
@MainActor final class FakeService:AliciaService {
 var offline=false, suspendUpload=false
 var actions:[[String:Any]]=[]
 var uploads:[VoiceSegment]=[]
 var waiter:CheckedContinuation<VoiceEvidenceResult?,Never>?
 var payload:VoiceEvidencePayload?
 var download:Data?
 func voiceAction(_ body:[String:Any]) async -> VoiceEvidenceResult? {
  actions.append(body)
  return offline ? nil : VoiceEvidenceResult(ok:true,deleted:body["action"] as? String == "delete_audio")
 }
 func voiceRecordings(recordingID:String) async -> VoiceEvidencePayload? { payload }
 func uploadVoice(recordingID:String,segment:VoiceSegment,file:URL) async -> VoiceEvidenceResult? {
  uploads.append(segment)
  if suspendUpload { return await withCheckedContinuation {waiter=$0} }
  return offline ? nil : VoiceEvidenceResult(ok:true,sha256:segment.sha256,bytes:segment.bytes)
 }
 func downloadVoice(recordingID:String,segmentID:String) async -> Data? { download }
}
final class VoiceEvidenceTests:XCTestCase {
 @MainActor func testSaveStatusSeparatesPhoneAndMacReceipts()async throws {
  let a=archive(),id=UUID().uuidString
  _ = try capture(a,id:id,count:600)
  XCTAssertTrue(a.recording(id)!.syncSummary.contains("saved on this phone"))
  XCTAssertFalse(a.recording(id)!.syncSummary.contains("phone and your Mac"))
  let service=FakeService();service.offline=true
  await a.sync(using:service)
  XCTAssertFalse(a.recording(id)!.syncSummary.contains("phone and your Mac"))
  service.offline=false;await a.sync(using:service)
  XCTAssertEqual(a.recording(id)!.syncSummary,"Audio saved on this phone and your Mac.")
 }
 @MainActor func context(_ id:String)->VoiceContext {
  VoiceContext(session_id:id,source:"ios_walk",started_at:"2026-09-05T01:02:03.000Z",timezone:"America/Los_Angeles",episode_id:"S15E07",episode_title:"Fixture only",episode_basis:"selected",frame_id:"fixture",question_presented:"A supplied question",playback_position_ms:12345)
 }
 @MainActor func archive()->VoiceArchive {
  let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  addTeardownBlock {try? FileManager.default.removeItem(at:root)}
  return VoiceArchive(root:root)
 }
 func buffer()->AVAudioPCMBuffer {
  let format=AVAudioFormat(standardFormatWithSampleRate:48000,channels:1)!
  let buffer=AVAudioPCMBuffer(pcmFormat:format,frameCapacity:1024)!
  buffer.frameLength=1024
  for i in 0..<1024 {buffer.floatChannelData![0][i]=0.125}
  return buffer
 }
 @MainActor func capture(_ archive:VoiceArchive,id:String,count:Int=2)throws->[VoiceSegment] {
  let sink=try archive.begin(id:id,context:context(id))
  let pcm=buffer();for _ in 0..<count {sink.append(pcm)}
  let result=sink.drain(close:true)
  XCTAssertNil(result.error)
  archive.addSegments(result.segments,to:id)
  return result.segments
 }
 @MainActor func testPCMBytesChecksumsAndSamplesSurviveSegmentRotation()throws {
  let a=archive(),id=UUID().uuidString
  let segments=try capture(a,id:id,count:600)
  XCTAssertGreaterThan(segments.count,1)
  var frames:Int64=0
  for segment in segments {
   let url=a.fileURL(id,segment.id),data=try Data(contentsOf:url)
   XCTAssertEqual(data.count,segment.bytes)
   XCTAssertEqual(SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined(),segment.sha256)
   let file=try AVAudioFile(forReading:url)
   frames += file.length
   let pcm=AVAudioPCMBuffer(pcmFormat:file.processingFormat,frameCapacity:AVAudioFrameCount(file.length))!
   try file.read(into:pcm)
   for i in 0..<Int(pcm.frameLength) {XCTAssertEqual(pcm.floatChannelData![0][i],0.125)}
  }
  XCTAssertEqual(frames,600*1024)
  XCTAssertEqual(a.recording(id)!.duration,Double(600*1024)/48000,accuracy:0.001)
 }
 @MainActor func testRemoteVersionsMergeWithoutLosingLocalWords()async throws {
  let a=archive(),id=UUID().uuidString;_ = try capture(a,id:id)
  a.addTranscript("local words",kind:"submitted",to:id)
  let f=FakeService();f.offline=true
  var remote=VoiceRecording(id:id,context:context(id))
  remote.transcripts=[VoiceTranscript(id:UUID().uuidString,text:"remote correction",kind:"correction",recorded_at:"2026-09-05T03:00:00Z")]
  let extra=VoiceSegment(id:UUID().uuidString,sha256:"test",started_at:"2026-09-05T02:00:00Z",ended_at:"2026-09-05T02:00:01Z",bytes:123,duration:1,sample_rate:48000,channels:1)
  remote.segments=[extra]
  f.payload=VoiceEvidencePayload(recordings:[remote])
  await a.refresh(using:f)
  XCTAssertEqual(a.recording(id)?.transcripts.count,2)
  XCTAssertEqual(a.recording(id)?.segments.count,2)
  XCTAssertEqual(a.recording(id)?.latestWords,"remote correction")
  XCTAssertEqual(a.recording(id)?.transcripts.first(where:{$0.kind=="submitted"})?.uploaded,false)
 }
 @MainActor func testCorrectionUsesAuthoredTimeAndPrecedesLaterSubmission()throws {
  var record=VoiceRecording(id:UUID().uuidString,context:context(UUID().uuidString))
  record.transcripts=[
   VoiceTranscript(id:"b",text:"new correction",kind:"correction",recorded_at:"2026-09-05T03:00:00Z"),
   VoiceTranscript(id:"a",text:"older correction",kind:"correction",recorded_at:"2026-09-05T02:00:00Z"),
   VoiceTranscript(id:"c",text:"submission",kind:"submitted",recorded_at:"2026-09-05T04:00:00Z")]
  XCTAssertEqual(record.latestWords,"new correction")
 }
 @MainActor func testDeleteBeforeUploadStillSyncsMetadata()async throws {
  let a=archive(),id=UUID().uuidString;_ = try capture(a,id:id)
  a.addTranscript("keep text",kind:"on_device",to:id)
  try a.deleteAudio(id)
  let f=FakeService();await a.sync(using:f)
  XCTAssertEqual(f.actions.compactMap{$0["action"] as? String},["delete_audio","create","transcript"])
  XCTAssertTrue(f.uploads.isEmpty)
  XCTAssertEqual(a.recording(id)?.transcripts.first?.uploaded,true)
 }
 @MainActor func testEmptyRecognitionStillRetainsAudioAndOriginalContext()throws {
  let a=archive(),id=UUID().uuidString;_ = try capture(a,id:id)
  XCTAssertTrue(a.hasAudio(id));XCTAssertTrue(a.recording(id)!.transcripts.isEmpty)
  XCTAssertEqual(a.recording(id)!.context.started_at,"2026-09-05T01:02:03.000Z")
  XCTAssertEqual(a.recording(id)!.context.episode_id,"S15E07")
 }
 @MainActor func testRelaunchKeepsVersionsAndRecoversUnindexedCAF()throws {
  let a=archive(),id=UUID().uuidString
  let sink=try a.begin(id:id,context:context(id));sink.append(buffer())
  let segments=sink.drain(close:true).segments // crash before index receipt
  a.addTranscript("original recognition",kind:"on_device",to:id)
  a.addTranscript("edited submission",kind:"submitted",to:id)
  let reopened=VoiceArchive(root:a.root)
  XCTAssertEqual(reopened.recording(id)?.segments.count,segments.count)
  XCTAssertEqual(reopened.recording(id)?.transcripts.map(\.text),["original recognition","edited submission"])
  XCTAssertEqual(reopened.recording(id)?.context.started_at,a.recording(id)?.context.started_at)
 }
 @MainActor func testOfflineUploadRetryDoesNotChangeIdentityTimeOrText()async throws {
  let a=archive(),id=UUID().uuidString;let segments=try capture(a,id:id)
  a.addTranscript("words",kind:"on_device",to:id)
  let f=FakeService();f.offline=true
  await a.sync(using:f);XCTAssertNotEqual(a.recording(id)?.contextUploaded,true)
  f.offline=false;await a.sync(using:f);await a.sync(using:f)
  XCTAssertEqual(f.uploads.map(\.id),segments.map(\.id))
  XCTAssertEqual(a.recording(id)?.segments.first?.uploaded,true)
  XCTAssertEqual(a.recording(id)?.transcripts.first?.uploaded,true)
  let starts=f.actions.filter{$0["action"] as? String == "create"}
  XCTAssertEqual(starts.count,2)
  XCTAssertEqual((starts[0]["context"] as? [String:Any])?["started_at"] as? String,(starts[1]["context"] as? [String:Any])?["started_at"] as? String)
 }
 @MainActor func testDeleteWhileUploadSuspendedCannotResurrectAudio()async throws {
  let a=archive(),id=UUID().uuidString;let segments=try capture(a,id:id)
  let f=FakeService();f.suspendUpload=true
  let syncing=Task {await a.sync(using:f)}
  while f.waiter==nil {await Task.yield()}
  try a.deleteAudio(id)
  await a.sync(using:f) // queues another pass behind the in-flight upload
  f.waiter?.resume(returning:VoiceEvidenceResult(ok:true,sha256:segments[0].sha256,bytes:segments[0].bytes))
  await syncing.value
  for _ in 0..<100 where a.recording(id)?.deletionUploaded != true {await Task.yield()}
  XCTAssertEqual(a.recording(id)?.deletionUploaded,true)
  XCTAssertFalse(FileManager.default.fileExists(atPath:a.fileURL(id,segments[0].id).path))
  XCTAssertTrue(f.actions.contains{$0["action"] as? String == "delete_audio"})
 }
 @MainActor func testOfflineDeleteSurvivesRelaunchAndRetries()async throws {
  let a=archive(),id=UUID().uuidString;_ = try capture(a,id:id)
  a.addTranscript("keep these words",kind:"on_device",to:id)
  try a.deleteAudio(id)
  let b=VoiceArchive(root:a.root),f=FakeService();f.offline=true
  await b.sync(using:f)
  XCTAssertEqual(b.recording(id)?.deleted,true);XCTAssertNotEqual(b.recording(id)?.deletionUploaded,true)
  f.offline=false;await b.sync(using:f)
  XCTAssertEqual(b.recording(id)?.deletionUploaded,true)
  XCTAssertEqual(b.recording(id)?.transcripts.first?.text,"keep these words")
  XCTAssertTrue(f.uploads.isEmpty)
 }
 @MainActor func testContextCannotBeReassignedToAnotherEpisode()throws {
  let a=archive(),id=UUID().uuidString;_ = try capture(a,id:id)
  var other=context(id);other.episode_id="S15E06"
  XCTAssertThrowsError(try a.begin(id:id,context:other))
 }
 @MainActor func testRemoteDeletionKeepsInspectableText()async throws {
  let a=archive(),f=FakeService(),id=UUID().uuidString
  var record=VoiceRecording(id:id,context:context(id));record.deleted=true
  record.transcripts=[VoiceTranscript(id:UUID().uuidString,text:"retained",kind:"on_device",recorded_at:voiceTimestamp())]
  f.payload=VoiceEvidencePayload(recordings:[record])
  await a.refresh(using:f)
  XCTAssertEqual(a.recording(id)?.deleted,true);XCTAssertEqual(a.recording(id)?.latestWords,"retained")
 }
 @MainActor func testReplayVerifiesDownloadedOriginal()async throws {
  let a=archive(),id=UUID().uuidString;let segment=try capture(a,id:id)[0]
  let bytes=try Data(contentsOf:a.fileURL(id,segment.id))
  try FileManager.default.removeItem(at:a.fileURL(id,segment.id))
  let f=FakeService();f.download=Data("wrong".utf8)
  let rejected=await a.playbackFiles(id,using:f);XCTAssertTrue(rejected.isEmpty)
  f.download=bytes;let files=await a.playbackFiles(id,using:f)
  XCTAssertEqual(files.count,1);XCTAssertEqual(try Data(contentsOf:files[0]),bytes)
 }
}
''')
evidence=Path(os.environ.get('ALICIA_TEST_EVIDENCE_DIR',str(work)))
evidence.mkdir(parents=True,exist_ok=True)
result=evidence/'voice-archive.xcresult'
env=dict(os.environ,DEVELOPER_DIR='/Applications/Xcode.app/Contents/Developer')
print('Temporary test project:',work,flush=True)
subprocess.run(['xcodebuild','-project',str(project),'-scheme','Alicia','-destination','platform=iOS Simulator,name=iPhone 17','-derivedDataPath',str(work/'DerivedData'),'-resultBundlePath',str(result),'-parallel-testing-enabled','NO','CODE_SIGNING_ALLOWED=NO','test'],env=env,check=True)
