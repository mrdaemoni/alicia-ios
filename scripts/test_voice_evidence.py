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
(folder/'VoiceEnrichment.swift').symlink_to(root/'Alicia/Core/VoiceEnrichment.swift')
(folder/'VoiceEvidence.swift').symlink_to(root/'Alicia/Core/VoiceEvidence.swift')
(folder/'VoiceProcessing.swift').symlink_to(root/'Alicia/Core/VoiceProcessing.swift')
context_source=(root/'Alicia/Core/Collaboration.swift').read_text().split('struct WorkDialogueContext:',1)[1].split('enum CollaborationReturnPreferences',1)[0]
(folder/'WorkDialogueContext.swift').write_text('import Foundation\nstruct WorkDialogueContext:'+context_source)
# Exercise the actual shared history mapper, with inert dependencies instead of AppStore.init/load.
app_source=(root/'Alicia/Core/AppStore.swift').read_text()
history_method=app_source.split('    private func historyMessage(',1)[1].split('\n    }',1)[0]
message_source=(root/'Alicia/Core/Models.swift').read_text().split('struct Message:',1)[1].split('\n}\n',1)[0]
history_source=(root/'Alicia/Core/EpisodeDay.swift').read_text().split('struct ConversationHistory:',1)[1].split('\n}\n',1)[0]
(folder/'HistoryRestoreHarness.swift').write_text('import Foundation\nstruct Message:'+message_source+'\n}\nstruct ConversationHistory:'+history_source+'\n}\n'+'''
@MainActor final class HistoryRestoreHarness {
 let voiceArchive:VoiceArchive
 let service:any AliciaService
 var messages:[Message]=[]
 init(_ archive:VoiceArchive, _ service:any AliciaService) {voiceArchive=archive;self.service=service}
 static func historyDate(_ raw:String)->Date {.distantPast}
 func historyMessage('''+history_method+'\n    }\n}\n')
(folder/'VoiceEvidenceTests.swift').write_text(r'''
import XCTest
import Foundation
import AVFoundation
import CryptoKit
protocol AliciaService {
 func finalizeVoice(_ seal:VoiceFinalization) async -> VoiceTransport<VoiceProcessingResponse>
 func retryVoiceTranscription(_ retry:VoiceTranscriptionRetry) async -> VoiceTransport<VoiceProcessingResponse>
 func voiceSubmissionStatus(_ requestID:String) async -> VoiceTransport<VoiceSubmissionStatus>
 func submitVoice(_ submission:VoiceSubmission) async -> VoiceTransport<VoiceSubmissionStatus>
 func voiceReplyURL(_ path:String) -> URL?
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
 var seals:[VoiceFinalization]=[], retries:[VoiceTranscriptionRetry]=[], sends:[VoiceSubmission]=[]
 var statusReads:[String]=[]
 var submitResult:VoiceTransport<VoiceSubmissionStatus> = .unavailable
 var statusResult:VoiceTransport<VoiceSubmissionStatus> = .unavailable
 var sealResult:VoiceTransport<VoiceProcessingResponse> = .unavailable
 var retryResult:VoiceTransport<VoiceProcessingResponse> = .unavailable
 var suspendSubmit=false, suspendSeal=false
 var submitWaiter:CheckedContinuation<VoiceTransport<VoiceSubmissionStatus>,Never>?
 var sealWaiter:CheckedContinuation<VoiceTransport<VoiceProcessingResponse>,Never>?
 func finalizeVoice(_ seal:VoiceFinalization) async -> VoiceTransport<VoiceProcessingResponse> {
  seals.append(seal)
  if suspendSeal { return await withCheckedContinuation {sealWaiter=$0} }
  return sealResult
 }
 func retryVoiceTranscription(_ retry:VoiceTranscriptionRetry) async -> VoiceTransport<VoiceProcessingResponse> {retries.append(retry);return retryResult}
 func voiceSubmissionStatus(_ requestID:String) async -> VoiceTransport<VoiceSubmissionStatus> {statusReads.append(requestID);return statusResult}
 func voiceReplyURL(_ path:String) -> URL? { URL(string:path,relativeTo:URL(string:"https://fixture.invalid")!) }
 func submitVoice(_ submission:VoiceSubmission) async -> VoiceTransport<VoiceSubmissionStatus> {
  sends.append(submission)
  if suspendSubmit {return await withCheckedContinuation {submitWaiter=$0}}
  return submitResult
 }
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

 @MainActor func macCapture(_ a:VoiceArchive,id:String,destination:String="dialogue",close:Bool=true)throws->VoiceAudioSink {
  let sink=try a.begin(id:id,context:context(id),review:VoiceReview(destination:destination,proactiveID:destination=="proactive" ? "original-ask" : "",proactiveExcerpt:"Original question"))
  sink.append(buffer())
  if close {a.addSegments(sink.drain(close:true).segments,to:id)}
  return sink
 }
 @MainActor func ready(_ a:VoiceArchive,id:String,destination:String="dialogue")async throws->FakeService {
  _ = try macCapture(a,id:id,destination:destination)
  XCTAssertTrue(a.finalize(id))
  var remote=a.recording(id)!
  let transcript=UUID().uuidString
  remote.transcription=VoiceTranscription(request_id:remote.finalization!.request_id,recording_id:id,state:"ready",attempt:1,transcript_id:transcript,retryable:false,
   recorded_seconds:remote.duration,processed_seconds:remote.duration,model:"local-fixture",language:"en",
   draft:VoiceMachineDraft(id:transcript,text:"Machine words for review",kind:"mac_whisper"))
  let f=FakeService();f.payload=VoiceEvidencePayload(recordings:[remote])
  await a.sync(using:f);await a.advanceProcessing(using:f)
  return f
 }
 @MainActor func testLegacyVoiceRecordWithoutEnrichmentDecodes() throws {
  let a=archive(),id=UUID().uuidString
  _ = try macCapture(a,id:id)
  let original = a.recording(id)!
  let data = try JSONEncoder().encode(original)
  var object = try JSONSerialization.jsonObject(with:data) as! [String:Any]
  object.removeValue(forKey:"enrichment")
  let restored = try JSONDecoder().decode(VoiceRecording.self,from:JSONSerialization.data(withJSONObject:object))
  XCTAssertNil(restored.enrichment)
  XCTAssertEqual(restored.id,id)
  XCTAssertEqual(restored.segments.count,original.segments.count)
  XCTAssertTrue(restored.transcripts.isEmpty)
 }
 @MainActor func testMacPauseDoesNotSealAndCompleteOrderedManifestSurvivesRestart()throws {
  let a=archive(),id=UUID().uuidString
  let sink=try macCapture(a,id:id,close:false)
  XCTAssertFalse(a.finalize(id),"An open tap cannot be sealed")
  let first=sink.drain(close:true).segments;a.addSegments(first,to:id)
  XCTAssertNil(a.recording(id)?.finalization)
  let second=try macCapture(a,id:id).drain().segments
  XCTAssertTrue(second.isEmpty) // closed capture already drained into archive
  let order=try JSONDecoder().decode([String].self,from:Data(contentsOf:a.directory(id).appendingPathComponent("capture-order.json")))
  XCTAssertEqual(order.count,2)
  let reopened=VoiceArchive(root:a.root)
  XCTAssertTrue(reopened.finalize(id))
  let seal=reopened.recording(id)!.finalization!
  XCTAssertEqual(seal.expected_segments.map(\.id),order)
  XCTAssertEqual(seal.expected_segments.map(\.sequence),[0,1])
  XCTAssertTrue(reopened.finalize(id));XCTAssertEqual(reopened.recording(id)?.finalization,seal)
  XCTAssertThrowsError(try reopened.begin(id:id,context:context(id)))
 }
 @MainActor func testMacCrashRecoversUnindexedOrderWithoutSortingUUID()throws {
  let a=archive(),id=UUID().uuidString
  let sink=try macCapture(a,id:id,close:false)
  let first=sink.drain(close:true).segments // crash before indexed receipt
  let recovered=VoiceArchive(root:a.root)
  XCTAssertTrue(recovered.finalize(id))
  XCTAssertEqual(recovered.recording(id)?.finalization?.expected_segments.map(\.id),first.map(\.id))
 }
 @MainActor func testSealRejectsMissingTailAndCaptureFailure()throws {
  let a=archive(),id=UUID().uuidString;_ = try macCapture(a,id:id)
  var order=try JSONDecoder().decode([String].self,from:Data(contentsOf:a.directory(id).appendingPathComponent("capture-order.json")))
  order.append(UUID().uuidString)
  try JSONEncoder().encode(order).write(to:a.directory(id).appendingPathComponent("capture-order.json"))
  XCTAssertFalse(a.finalize(id));XCTAssertNil(a.recording(id)?.finalization)
  let b=archive(),other=UUID().uuidString;_ = try macCapture(b,id:other)
  b.noteCaptureError("write failed",id:other)
  XCTAssertFalse(VoiceArchive(root:b.root).finalize(other))
 }
 @MainActor func testMachineDraftIsNotSubmittedAndCannotEraseEditedWords()async throws {
  let a=archive(),id=UUID().uuidString,f=try await ready(a,id:id)
  XCTAssertEqual(a.recording(id)?.review?.text,"Machine words for review")
  XCTAssertTrue(a.recording(id)!.transcripts.isEmpty)
  a.editReview(id,text:"My exact edited words")
  var remote=f.payload!.recordings[0];remote.transcription!.draft!.text="Late machine revision"
  f.payload=VoiceEvidencePayload(recordings:[remote])
  await a.refresh(using:f);await a.advanceProcessing(using:f)
  XCTAssertEqual(a.recording(id)?.review?.text,"My exact edited words")
  XCTAssertEqual(VoiceArchive(root:a.root).recording(id)?.review?.text,"My exact edited words")
 }
 @MainActor func testMacFinalizeRetryPreservesReceiptAndDeletedLateResultCannotPublish()async throws {
  let a=archive(),id=UUID().uuidString;_ = try macCapture(a,id:id);XCTAssertTrue(a.finalize(id))
  let f=FakeService();await a.sync(using:f)
  await a.advanceProcessing(using:f);await a.advanceProcessing(using:f)
  XCTAssertEqual(f.seals.count,2);XCTAssertEqual(f.seals[0],f.seals[1])
  f.suspendSeal=true
  let work=Task {await a.advanceProcessing(using:f)}
  while f.sealWaiter==nil {await Task.yield()}
  try a.deleteAudio(id)
  let state=VoiceTranscription(request_id:f.seals[0].request_id,recording_id:id,state:"queued")
  f.sealWaiter?.resume(returning:.value(VoiceProcessingResponse(ok:true,transcription:state)))
  await work.value
  XCTAssertNil(a.recording(id)?.transcription);XCTAssertTrue(a.recording(id)!.deleted)
 }
 @MainActor func testPendingSendFreezesTargetAndTextAcrossRestart()async throws {
  let a=archive(),id=UUID().uuidString,f=try await ready(a,id:id,destination:"proactive")
  a.editReview(id,text:"Exactly these words")
  XCTAssertTrue(a.prepareSubmission(id,voice:false))
  let initial=a.recording(id)!.submission!
  a.editReview(id,text:"Must not replace a pending send")
  await a.advanceProcessing(using:f)
  XCTAssertEqual(f.sends.count,1)
  XCTAssertEqual(f.sends[0].text,"Exactly these words")
  XCTAssertEqual(f.sends[0].body["proactive_id"] as? String,"original-ask")
  XCTAssertNil(f.sends[0].body["voice"],"Proactive route does not support spoken replies")
  XCTAssertEqual(f.sends[0].body["episode_id"] as? String,"S15E07")
  let reopened=VoiceArchive(root:a.root)
  await reopened.advanceProcessing(using:f)
  XCTAssertEqual(f.sends.count,1,"An unavailable status must not replay")
  XCTAssertEqual(reopened.recording(id)?.submission?.requestID,initial.requestID)
  XCTAssertTrue(reopened.recording(id)!.transcripts.isEmpty)
 }
 @MainActor func testOnlyDefiniteUnknownReceiptPermitsIdenticalRepost()async throws {
  let a=archive(),id=UUID().uuidString,f=try await ready(a,id:id)
  XCTAssertTrue(a.prepareSubmission(id,voice:false));await a.advanceProcessing(using:f)
  let sent=f.sends[0]
  f.statusResult = .notFound
  await a.advanceProcessing(using:f)
  XCTAssertEqual(f.sends.count,2);XCTAssertEqual(f.sends[1],sent)
  XCTAssertEqual(sent.body["episode_id"] as? String,"S15E07")
  f.statusResult = .value(VoiceSubmissionStatus(request_id:sent.requestID,state:"outcome_unknown"))
  await a.advanceProcessing(using:f)
  f.statusResult = .notFound;await a.advanceProcessing(using:f)
  XCTAssertEqual(f.sends.count,2,"An uncertain effect is never retried automatically")
 }
 @MainActor func testCompletedReceiptAddsOneSubmittedVersionAndNeverReexecutes()async throws {
  let a=archive(),id=UUID().uuidString,f=try await ready(a,id:id)
  XCTAssertTrue(a.prepareSubmission(id,voice:false))
  let request=a.recording(id)!.submission!.requestID
  f.submitResult = .value(VoiceSubmissionStatus(request_id:request,state:"completed",reply_id:request,text:"A short saved reply"))
  await a.advanceProcessing(using:f);await a.advanceProcessing(using:f)
  XCTAssertEqual(f.sends.count,1)
  XCTAssertEqual(a.recording(id)?.transcripts.count,1)
  XCTAssertEqual(a.recording(id)?.transcripts[0].id,request)
  XCTAssertEqual(a.recording(id)?.transcripts[0].uploaded,true)
 }
 @MainActor func testWrongReplyReceiptCannotCompleteSend()async throws {
  let a=archive(),id=UUID().uuidString,f=try await ready(a,id:id)
  XCTAssertTrue(a.prepareSubmission(id,voice:false))
  f.submitResult = .value(VoiceSubmissionStatus(request_id:UUID().uuidString,state:"completed"))
  await a.advanceProcessing(using:f)
  XCTAssertNil(a.recording(id)?.submissionStatus)
  XCTAssertTrue(a.recording(id)!.transcripts.isEmpty)
 }
 @MainActor func testSuspendedSendLocksEditorAndDeletionWins()async throws {
  let a=archive(),id=UUID().uuidString,f=try await ready(a,id:id)
  XCTAssertTrue(a.prepareSubmission(id,voice:false));f.suspendSubmit=true
  let work=Task {await a.advanceProcessing(using:f)}
  while f.submitWaiter==nil {await Task.yield()}
  let request=f.sends[0].requestID
  a.editReview(id,text:"Do not transfer to old request")
  XCTAssertEqual(a.recording(id)?.review?.text,"Machine words for review")
  try a.deleteAudio(id)
  f.submitWaiter?.resume(returning:.value(VoiceSubmissionStatus(request_id:request,state:"completed")))
  await work.value
  XCTAssertNil(a.recording(id)?.submissionStatus)
 }
 @MainActor func testWalkRetryKeepsExactEpisodeQuestionAndMachineSource()async throws {
  let a=archive(),id=UUID().uuidString,f=try await ready(a,id:id,destination:"walk")
  XCTAssertTrue(a.prepareSubmission(id,voice:false));await a.advanceProcessing(using:f)
  await VoiceArchive(root:a.root).advanceProcessing(using:f)
  XCTAssertEqual(f.sends.count,2);XCTAssertEqual(f.sends[0],f.sends[1])
  XCTAssertEqual(f.sends[0].body["topic"] as? String,"A supplied question")
  XCTAssertEqual(f.sends[0].body["transcript_id"] as? String,a.recording(id)?.transcription?.transcript_id)
  XCTAssertTrue(f.statusReads.isEmpty)
 }
 @MainActor func testRejectedSendCanOnlyBeEditedExplicitlyWithNewReceipt()async throws {
  let a=archive(),id=UUID().uuidString,f=try await ready(a,id:id)
  XCTAssertTrue(a.prepareSubmission(id,voice:false));let original=a.recording(id)!.submission!.requestID
  f.submitResult = .rejected("Invalid text")
  await a.advanceProcessing(using:f);await a.advanceProcessing(using:f)
  XCTAssertEqual(f.sends.count,1);a.editReview(id,text:"Ignored")
  XCTAssertNotEqual(a.recording(id)?.review?.text,"Ignored")
  a.editRejectedSubmission(id);a.editReview(id,text:"New exact text")
  XCTAssertTrue(a.prepareSubmission(id,voice:false));XCTAssertNotEqual(a.recording(id)?.submission?.requestID,original)
 }

 @MainActor func testDefiniteFailedStatusCanReopenExactWordsWithNewReceiptOnlyExplicitly()async throws {
  let a=archive(),id=UUID().uuidString,f=try await ready(a,id:id,destination:"proactive")
  a.editReview(id,text:"My reviewed words, kept exactly.")
  XCTAssertTrue(a.prepareSubmission(id,voice:false));await a.advanceProcessing(using:f)
  let original=a.recording(id)!.submission!
  f.statusResult = .value(VoiceSubmissionStatus(request_id:original.requestID,state:"failed",error:"The original prompt is unavailable."))
  await a.advanceProcessing(using:f);await a.advanceProcessing(using:f)
  XCTAssertEqual(f.sends.count,1,"A definite failure must still not retry automatically")
  XCTAssertTrue(a.recording(id)!.canReopenSubmission)
  XCTAssertEqual(a.recording(id)?.submissionError,"The original prompt is unavailable.")
  let restored=VoiceArchive(root:a.root)
  restored.editRejectedSubmission(id)
  XCTAssertEqual(restored.recording(id)?.review?.text,original.text)
  XCTAssertNil(restored.recording(id)?.submission);XCTAssertNil(restored.recording(id)?.submissionStatus)
  XCTAssertTrue(restored.prepareSubmission(id,voice:false))
  let next=restored.recording(id)!.submission!
  XCTAssertNotEqual(next.requestID,original.requestID)
  XCTAssertEqual(next.text,original.text);XCTAssertEqual(next.proactiveID,original.proactiveID)
  XCTAssertEqual(next.episodeID,original.episodeID);XCTAssertEqual(next.transcriptID,original.transcriptID)
 }
 @MainActor func testUnknownOutcomeNeverReopensOrRotatesPendingSend()async throws {
  let a=archive(),id=UUID().uuidString,f=try await ready(a,id:id)
  a.editReview(id,text:"Keep these exact uncertain words")
  XCTAssertTrue(a.prepareSubmission(id,voice:false));await a.advanceProcessing(using:f)
  let original=a.recording(id)!.submission!
  f.statusResult = .value(VoiceSubmissionStatus(request_id:original.requestID,state:"outcome_unknown",error:"Effects are uncertain."))
  await a.advanceProcessing(using:f)
  let restored=VoiceArchive(root:a.root)
  XCTAssertFalse(restored.recording(id)!.canReopenSubmission)
  restored.editRejectedSubmission(id);restored.editReview(id,text:"Must not replace uncertain send")
  XCTAssertEqual(restored.recording(id)?.submission,original)
  XCTAssertEqual(restored.recording(id)?.review?.text,original.text)
  XCTAssertFalse(restored.prepareSubmission(id,voice:false))
  await restored.advanceProcessing(using:f)
  XCTAssertEqual(f.sends.count,1)
  var contradictory=restored.recording(id)!;contradictory.submissionRejected=true
  XCTAssertFalse(contradictory.canReopenSubmission,"Unknown effects win over an old rejection flag")
 }

 @MainActor func testExhaustedAutomaticAttemptsRequireExplicitStableRetry()async throws {
  let a=archive(),id=UUID().uuidString;_ = try macCapture(a,id:id);XCTAssertTrue(a.finalize(id))
  var remote=a.recording(id)!
  remote.transcription=VoiceTranscription(request_id:remote.finalization!.request_id,recording_id:id,state:"failed",attempt:3,
   error_code:"attempts_exhausted",error:"Automatic attempts exhausted",retryable:false)
  let f=FakeService();f.payload=VoiceEvidencePayload(recordings:[remote]);await a.sync(using:f)
  await a.advanceProcessing(using:f);await a.advanceProcessing(using:f)
  XCTAssertTrue(f.retries.isEmpty,"Exhausted automatic attempts must not reset themselves")
  XCTAssertTrue(a.recording(id)!.transcription!.canRetryExplicitly)
  a.retryTranscription(id);let event=a.recording(id)!.pendingTranscriptionRetry!
  a.retryTranscription(id);XCTAssertEqual(a.recording(id)?.pendingTranscriptionRetry,event)
  await a.advanceProcessing(using:f)
  let restored=VoiceArchive(root:a.root);restored.retryTranscription(id)
  await restored.advanceProcessing(using:f)
  XCTAssertEqual(f.retries,[event,event],"Lost response and relaunch retain one explicit retry identity")
  XCTAssertEqual(restored.recording(id)?.finalization,a.recording(id)?.finalization)
  var permanent=remote.transcription!;permanent.error_code="invalid_manifest"
  XCTAssertFalse(permanent.canRetryExplicitly,"Other permanent failures remain non-retryable")
 }

 @MainActor func testPausedDialogueStartsNewAudioAfterEpisodeOrTargetChanges()throws {
  let a=archive(),oldID=UUID().uuidString;_ = try macCapture(a,id:oldID)
  let original=a.recording(oldID)!,hashes=original.segments.map(\.sha256)
  XCTAssertTrue(original.canResumeDialogue(episodeID:"S15E07",proactiveID:""))
  XCTAssertFalse(original.canResumeDialogue(episodeID:"S15E08",proactiveID:""))
  XCTAssertFalse(original.canResumeDialogue(episodeID:"S15E07",proactiveID:"another-ask"))
  let currentEpisode="S15E08"
  let nextID=original.canResumeDialogue(episodeID:currentEpisode,proactiveID:"") ? oldID : UUID().uuidString
  var nextContext=context(nextID);nextContext.episode_id=currentEpisode
  let sink=try a.begin(id:nextID,context:nextContext,review:VoiceReview(destination:"dialogue"))
  sink.append(buffer());a.addSegments(sink.drain(close:true).segments,to:nextID)
  XCTAssertNotEqual(nextID,oldID)
  XCTAssertEqual(a.recording(oldID)?.context.episode_id,"S15E07")
  XCTAssertEqual(a.recording(oldID)?.segments.map(\.sha256),hashes)
  XCTAssertNil(a.recording(oldID)?.finalization)
  XCTAssertEqual(a.recording(nextID)?.context.episode_id,"S15E08")
  XCTAssertTrue(a.hasAudio(oldID));XCTAssertTrue(a.hasAudio(nextID))
 }
 func testStatusHTTPClassificationAndOpenProvenance()throws {
  let data=Data(#"{"error":"invalid"}"#.utf8)
  for code in [400,409] {if case .rejected = decodeVoiceResponse(VoiceSubmissionStatus.self,data:data,status:code) {} else {XCTFail("Expected definite rejection")}}
  for code in [401,403,500,503,404] {if case .unavailable = decodeVoiceResponse(VoiceSubmissionStatus.self,data:data,status:code) {} else {XCTFail("Unsafe replay classification")}}
  if case .notFound = decodeVoiceResponse(VoiceSubmissionStatus.self,data:data,status:404,allowNotFound:true) {} else {XCTFail("Missing reserve must be distinct")}
  let machine=try JSONDecoder().decode(VoiceMachineDraft.self,from:Data(#"{"id":"test","text":"text","kind":"mac_whisper","provenance":{"engine":"whisper","coverage":1.0,"warnings":["review"],"checked":true,"unknown":null}}"#.utf8))
  XCTAssertEqual(try JSONDecoder().decode(VoiceMachineDraft.self,from:JSONEncoder().encode(machine)),machine)
 }

 @MainActor func testHistoricalAudioNeverAutoSealsAndCannotBeExtendedAsMacCapture()async throws {
  let a=archive(),id=UUID().uuidString;_ = try capture(a,id:id)
  XCTAssertFalse(a.finalize(id))
  XCTAssertThrowsError(try a.begin(id:id,context:context(id),review:VoiceReview(destination:"dialogue")))
  let f=FakeService();await a.sync(using:f);await a.advanceProcessing(using:f)
  XCTAssertTrue(f.seals.isEmpty)
 }
 @MainActor func testRetryEventAndEditedWordsSurviveUnknownRetryResponse()async throws {
  let a=archive(),id=UUID().uuidString;_ = try macCapture(a,id:id);XCTAssertTrue(a.finalize(id))
  var remote=a.recording(id)!
  remote.transcription=VoiceTranscription(request_id:remote.finalization!.request_id,recording_id:id,state:"failed",attempt:1,error:"Fixture decoder unavailable",retryable:true)
  let f=FakeService();f.payload=VoiceEvidencePayload(recordings:[remote]);await a.sync(using:f);await a.advanceProcessing(using:f)
  a.retryTranscription(id);let event=a.recording(id)!.pendingTranscriptionRetry!
  await a.advanceProcessing(using:f)
  let restored=VoiceArchive(root:a.root);restored.retryTranscription(id);await restored.advanceProcessing(using:f)
  XCTAssertEqual(f.retries,[event,event])
  XCTAssertEqual(restored.recording(id)?.finalization,a.recording(id)?.finalization)
 }
 func testCompletedReceiptAcceptsNumericOrStringMessageID()throws {
  for raw in [#"{"request_id":"id","state":"completed","text":"saved","message_id":42}"#,
              #"{"request_id":"id","state":"completed","text":"saved","message_id":"42"}"#] {
   let status=try JSONDecoder().decode(VoiceSubmissionStatus.self,from:Data(raw.utf8))
   XCTAssertEqual(status.message_id,42);XCTAssertEqual(status.text,"saved")
  }
 }

 @MainActor func testEmptyTapCallbackDoesNotInventMissingTail()throws {
  let a=archive(),id=UUID().uuidString
  let sink=try macCapture(a,id:id,close:false)
  let empty=buffer();empty.frameLength=0;sink.append(empty)
  a.addSegments(sink.drain(close:true).segments,to:id)
  XCTAssertTrue(a.finalize(id));XCTAssertEqual(a.recording(id)?.finalization?.expected_segments.count,1)
 }

 func testTerminalStreamFramesEndWaitingButAreNotSavedReceipts() {
  XCTAssertTrue(voiceStreamFinished(#"data: {"done":true,"reply_id":"id"}"#))
  XCTAssertTrue(voiceStreamFinished(#"data:{"error":"connection interrupted"}"#))
  XCTAssertFalse(voiceStreamFinished(#"data: {"t":"done"}"#))
  XCTAssertFalse(voiceStreamFinished(#"data: {"done":false}"#))
  XCTAssertFalse(voiceStreamFinished(": keep-alive"))
 }
 func testStreamVoiceNeedsAnExactCompletedReceipt() {
  var stream=VoiceReplyStreamReceipt()
  XCTAssertFalse(stream.receive(#"data: {"reply_id":"reply-a"}"#))
  XCTAssertFalse(stream.receive(#"data: {"voice":"/api/voice/saved.wav"}"#))
  XCTAssertTrue(stream.receive(#"data: {"done":true,"message_id":"42","reply_id":"reply-a"}"#))
  let complete=VoiceSubmissionStatus(request_id:"request-a",state:"completed",reply_id:"reply-a")
  XCTAssertEqual(stream.confirmed(complete,requestID:"request-a").voice_path,"/api/voice/saved.wav")
  XCTAssertNil(stream.confirmed(complete,requestID:"request-b").voice_path)
  XCTAssertNil(stream.confirmed(VoiceSubmissionStatus(request_id:"request-a",state:"processing",reply_id:"reply-a"),requestID:"request-a").voice_path)
  XCTAssertNil(stream.confirmed(VoiceSubmissionStatus(request_id:"request-a",state:"completed",reply_id:"reply-b"),requestID:"request-a").voice_path)
  XCTAssertNil(stream.confirmed(VoiceSubmissionStatus(request_id:"request-a",state:"completed"),requestID:"request-a").voice_path)
 }
 func testStreamDoesNotTransferMediaAcrossConflictingReplyIDs() {
  var stream=VoiceReplyStreamReceipt()
  _=stream.receive(#"data: {"reply_id":"first"}"#)
  _=stream.receive(#"data: {"voice":"/api/voice/first.wav"}"#)
  _=stream.receive(#"data: {"done":true,"reply_id":"second"}"#)
  XCTAssertNil(stream.confirmed(VoiceSubmissionStatus(request_id:"request",state:"completed",reply_id:"second"),requestID:"request").voice_path)
  var noMedia=VoiceReplyStreamReceipt()
  for line in [": keep-alive", "data: malformed", #"data: {"t":"voice"}"#, #"data: {"voice":" "}"#] {_=noMedia.receive(line)}
  XCTAssertNil(noMedia.confirmed(VoiceSubmissionStatus(request_id:"request",state:"completed",reply_id:"reply"),requestID:"request").voice_path)
 }
 func testStatusWithoutMediaKeepsOnlyItsExactConfirmedReplyAudio()throws {
  let previous=VoiceSubmissionStatus(request_id:"request",state:"completed",reply_id:"reply",voice_path:"/api/voice/retained.wav")
  let restored=try JSONDecoder().decode(VoiceSubmissionStatus.self,from:JSONEncoder().encode(previous))
  let fresh=VoiceSubmissionStatus(request_id:"request",state:"completed",reply_id:"reply")
  XCTAssertEqual(fresh.retainingVoiceMedia(from:restored).voice_path,previous.voice_path)
  XCTAssertNil(VoiceSubmissionStatus(request_id:"other",state:"completed",reply_id:"reply").retainingVoiceMedia(from:restored).voice_path)
  XCTAssertNil(VoiceSubmissionStatus(request_id:"request",state:"completed",reply_id:"other").retainingVoiceMedia(from:restored).voice_path)
  XCTAssertNil(VoiceSubmissionStatus(request_id:"request",state:"processing",reply_id:"reply",voice_path:"premature").retainingVoiceMedia(from:restored).voice_path)
 }
 @MainActor func testConfirmedMediaPersistsAndRestoresExactHistoryReply()async throws {
  let a=archive(),id=UUID().uuidString,f=try await ready(a,id:id)
  XCTAssertTrue(a.prepareSubmission(id,voice:true))
  let request=a.recording(id)!.submission!.requestID
  f.submitResult = .value(VoiceSubmissionStatus(request_id:request,state:"completed",reply_id:"exact-reply",message_id:42,voice_path:"/api/voice/saved.wav"))
  await a.advanceProcessing(using:f)
  let restored=VoiceArchive(root:a.root),harness=HistoryRestoreHarness(restored,f)
  let turn=ConversationHistory.Turn(id:"history-row",ts:"",role:"assistant",content:"The saved answer",source:"ios",reply_id:"exact-reply",recording_id:id)
  let message=harness.historyMessage(turn)
  XCTAssertEqual(message.voiceURL?.absoluteString,"https://fixture.invalid/api/voice/saved.wav")
  XCTAssertEqual(message.messageID,42);XCTAssertEqual(message.replyID,"exact-reply")
  XCTAssertEqual(message.text,"The saved answer")
  var unrelated=turn;unrelated.reply_id="different-reply"
  XCTAssertNil(harness.historyMessage(unrelated).voiceURL)
  XCTAssertFalse(harness.historyMessage(unrelated).canReadVoiceReply)
  var user=turn;user.role="user"
  XCTAssertNil(harness.historyMessage(user).voiceURL);XCTAssertFalse(harness.historyMessage(user).canReadVoiceReply)
  await restored.advanceProcessing(using:f);XCTAssertEqual(f.sends.count,1,"Restoring playback never reexecutes the chat")
 }
 @MainActor func testLostMediaRestoresExplicitReadAloudOnlyForRequestedVoice()async throws {
  for wantsVoice in [true,false] {
   let a=archive(),id=UUID().uuidString,f=try await ready(a,id:id)
   XCTAssertTrue(a.prepareSubmission(id,voice:wantsVoice))
   let request=a.recording(id)!.submission!.requestID
   f.submitResult = .value(VoiceSubmissionStatus(request_id:request,state:"completed",reply_id:"reply",text:"Saved answer"))
   await a.advanceProcessing(using:f)
   let h=HistoryRestoreHarness(VoiceArchive(root:a.root),f)
   let row=ConversationHistory.Turn(id:"history-row",ts:"",role:"assistant",content:"Saved answer",source:"ios",reply_id:"reply",recording_id:id)
   let message=h.historyMessage(row)
   XCTAssertNil(message.voiceURL);XCTAssertEqual(message.canReadVoiceReply,wantsVoice)
   XCTAssertEqual(message.text,"Saved answer")
  }
 }
 @MainActor func testHistoryRefreshKeepsExistingTypedStreamMediaOnlyForItsReply() {
  let h=HistoryRestoreHarness(archive(),FakeService()),url=URL(string:"https://fixture.invalid/voice.wav")!
  h.messages=[Message(sender:.alicia,text:"Typed reply",replyID:"typed-reply",voiceURL:url)]
  var row=ConversationHistory.Turn(id:"row",ts:"",role:"assistant",content:"Typed reply",source:"ios",reply_id:"typed-reply")
  XCTAssertEqual(h.historyMessage(row).voiceURL,url)
  row.reply_id=nil;XCTAssertNil(h.historyMessage(row).voiceURL)
 }
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
