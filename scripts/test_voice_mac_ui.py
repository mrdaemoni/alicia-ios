"""Temporary XCUITest target for the real app; no changes to its project file."""
import json, os, pathlib, plistlib, shutil, subprocess, tempfile
import xml.etree.ElementTree as ET
root = pathlib.Path(__file__).resolve().parents[1]
work = pathlib.Path(tempfile.mkdtemp(prefix='alicia-context-ui-'))
print(work, flush=True)
project = work / 'Alicia.xcodeproj'
shutil.copytree(root / 'Alicia.xcodeproj', project)
for folder in ('Alicia','AliciaWidgets'):
    (work / folder).symlink_to(root / folder, target_is_directory=True)
for source in root.glob('*.plist'):
    (work / source.name).symlink_to(source)
p = json.loads(subprocess.check_output(['plutil','-convert','json','-o','-',str(project/'project.pbxproj')]))
o=p['objects']; r=o[p['rootObject']]
def add(suffix, value):
    key='CC00000000000000000000'+suffix
    o[key]=value
    return key
ref=add('01',dict(isa='PBXFileReference',explicitFileType='wrapper.cfbundle',path='ContextUITests.xctest',sourceTree='BUILT_PRODUCTS_DIR'))
group=add('02',dict(isa='PBXFileSystemSynchronizedRootGroup',explicitFileTypes={},explicitFolders=[],path='ContextUITests',sourceTree='<group>'))
sources=add('03',dict(isa='PBXSourcesBuildPhase',buildActionMask='2147483647',files=[],runOnlyForDeploymentPostprocessing='0'))
frameworks=add('04',dict(isa='PBXFrameworksBuildPhase',buildActionMask='2147483647',files=[],runOnlyForDeploymentPostprocessing='0'))
configs=[]
for index, name in enumerate(('Debug','Release')):
    configs.append(add('0'+str(5+index),dict(isa='XCBuildConfiguration',name=name,buildSettings=dict(
        CODE_SIGN_STYLE='Automatic',GENERATE_INFOPLIST_FILE='YES',IPHONEOS_DEPLOYMENT_TARGET='18.0',
        PRODUCT_BUNDLE_IDENTIFIER='com.myalicia.contextuitests',PRODUCT_NAME='$(TARGET_NAME)',
        SWIFT_VERSION='5.0',TARGETED_DEVICE_FAMILY='1,2',TEST_TARGET_NAME='Alicia',SDKROOT='iphoneos'))))
configlist=add('07',dict(isa='XCConfigurationList',buildConfigurations=configs,defaultConfigurationIsVisible='0',defaultConfigurationName='Release'))
proxy=add('08',dict(isa='PBXContainerItemProxy',containerPortal=p['rootObject'],proxyType='1',remoteGlobalIDString='AA0000000000000000000006',remoteInfo='Alicia'))
dep=add('09',dict(isa='PBXTargetDependency',target='AA0000000000000000000006',targetProxy=proxy))
target=add('10',dict(isa='PBXNativeTarget',name='ContextUITests',productName='ContextUITests',productType='com.apple.product-type.bundle.ui-testing',
    productReference=ref,buildConfigurationList=configlist,buildPhases=[sources,frameworks],buildRules=[],dependencies=[dep],fileSystemSynchronizedGroups=[group]))
r['targets'].append(target);o[r['mainGroup']]['children'].append(group);o[r['productRefGroup']]['children'].append(ref)
(project/'project.pbxproj').write_bytes(plistlib.dumps(p))
scheme=project/'xcshareddata/xcschemes/Alicia.xcscheme';tree=ET.parse(scheme)
refattrs=dict(BuildableIdentifier='primary',BlueprintIdentifier=target,BuildableName='ContextUITests.xctest',BlueprintName='ContextUITests',ReferencedContainer='container:Alicia.xcodeproj')
entry=ET.SubElement(tree.find('.//BuildActionEntries'),'BuildActionEntry',dict(buildForTesting='YES',buildForRunning='NO',buildForProfiling='NO',buildForArchiving='NO',buildForAnalyzing='NO'))
ET.SubElement(entry,'BuildableReference',refattrs)
test=ET.SubElement(tree.find('.//Testables'),'TestableReference',dict(skipped='NO'));ET.SubElement(test,'BuildableReference',refattrs)
tree.write(scheme,encoding='utf-8',xml_declaration=True)
(work/'ContextUITests').mkdir()
(work/'ContextUITests/ContextUITests.swift').write_text(r'''
import XCTest
final class ContextUITests: XCTestCase {
 func capture(_ name:String, app:XCUIApplication) {
  let shot=XCTAttachment(screenshot:app.screenshot());shot.name=name;shot.lifetime = .keepAlways;add(shot)
 }
 func reveal(_ element:XCUIElement,app:XCUIApplication,up:Bool=true) {
  for _ in 0..<15 {
   let bottom=app.keyboards.firstMatch.exists ? app.keyboards.firstMatch.frame.minY : app.frame.maxY-70
   if element.isHittable && element.frame.midY > 140 && element.frame.maxY < bottom {return}
   let start=app.coordinate(withNormalizedOffset:.zero).withOffset(CGVector(dx:10,dy:min(bottom-20,app.frame.height*0.72)))
   let end=app.coordinate(withNormalizedOffset:.zero).withOffset(CGVector(dx:10,dy:190))
   if up {start.press(forDuration:0.05,thenDragTo:end)} else {end.press(forDuration:0.05,thenDragTo:start)}
  }
 }
 func openRecord(_ app:XCUIApplication) {
  let archive=app.buttons["voice.recordings"]
  XCTAssertTrue(archive.waitForExistence(timeout:10));archive.tap()
  let row=app.buttons.matching(NSPredicate(format:"label CONTAINS %@","Preview · Endings Chosen")).firstMatch
  XCTAssertTrue(row.waitForExistence(timeout:10));row.tap()
 }
 func testCaptureOnlyMicrophonePreviewExplainsMacProcessing() {
  continueAfterFailure=false
  let app=XCUIApplication();app.launchArguments=["--voice-evidence-preview","--voice-mac-preview","--voice-mac-recording","--voice-save-preview","--episode-day-preview","--episode-microphone-on","--reduce-motion-preview"];app.launch()
  let microphone=app.otherElements["walk.microphoneState"]
  XCTAssertTrue(microphone.waitForExistence(timeout:10))
  XCTAssertTrue(microphone.label.contains("MICROPHONE ON"))
  XCTAssertTrue(microphone.label.contains("Your Mac transcribes after Finish"))
  XCTAssertFalse(app.textViews["Your walk reflection"].exists)
  XCTAssertTrue(app.staticTexts["Preview of microphone-on UI. No audio is recorded or sent."].exists)
  capture("capture-only-microphone-preview",app:app)
 }
 func testDialogueReviewsExactWordsAndKeepsIndependentTypedDraft() {
  continueAfterFailure=false
  let app=XCUIApplication();app.launchArguments=["--voice-evidence-preview","--voice-mac-preview","--tab","dialogue"];app.launch()
  let composer=app.textFields["dialogue.composer"]
  XCTAssertTrue(composer.waitForExistence(timeout:10));composer.tap();composer.typeText("Typed note must stay")
  let expectedTyped=composer.value as? String
  openRecord(app)
  let editor=app.textViews["voice.macDraft"]
  reveal(editor,app:app);XCTAssertTrue(editor.isHittable)
  capture("dialogue-mac-draft",app:app)
  editor.tap();editor.typeText(" My reviewed addition.")
  XCTAssertTrue((editor.value as? String ?? "").contains("My reviewed addition"))
  let done=app.buttons["voice.doneEditing"]
  XCTAssertTrue(done.waitForExistence(timeout:5));XCTAssertTrue(done.isHittable)
  capture("dialogue-review-keyboard-done",app:app);done.tap()
  let send=app.buttons["voice.sendReviewed"]
  reveal(send,app:app);XCTAssertTrue(send.isHittable);send.tap()
  let pending=app.staticTexts["Checking the saved send receipt. Your exact words are kept here."]
  reveal(pending,app:app);XCTAssertTrue(pending.exists)
  capture("dialogue-frozen-pending-send",app:app)
  app.navigationBars.buttons.element(boundBy:0).tap()
  app.buttons["CLOSE"].tap()
  XCTAssertEqual(app.textFields["dialogue.composer"].value as? String,expectedTyped)
  openRecord(app);reveal(editor,app:app)
  XCTAssertTrue((editor.value as? String ?? "").contains("My reviewed addition"))
  XCTAssertFalse(app.buttons["voice.sendReviewed"].exists)
 }
 func testWalkMacReviewAndOriginalStayReachable() {
  continueAfterFailure=false
  let app=XCUIApplication();app.launchArguments=["--voice-evidence-preview","--voice-mac-preview","--voice-save-preview"];app.launch()
  let editor=app.textViews["voice.macDraft"]
  XCTAssertTrue(editor.waitForExistence(timeout:10));reveal(editor,app:app)
  XCTAssertTrue(editor.isHittable)
  editor.tap();editor.typeText(" A walk edit.")
  let done=app.buttons["voice.doneEditing"]
  XCTAssertTrue(done.waitForExistence(timeout:5));XCTAssertTrue(done.isHittable)
  capture("walk-review-keyboard-done",app:app);done.tap()
  capture("walk-mac-review",app:app)
  XCTAssertTrue(app.buttons["REVIEW ORIGINAL AUDIO"].exists)
  app.buttons["REVIEW ORIGINAL AUDIO"].tap()
  XCTAssertTrue(app.buttons["voice.playOriginal"].waitForExistence(timeout:10))
  capture("walk-original-with-mac-draft",app:app)
 }
 func testWaitingShowsForegroundUploadLimitAndNoSend() {
  continueAfterFailure=false
  let app=XCUIApplication();app.launchArguments=["--voice-evidence-preview","--voice-mac-preview","--voice-mac-waiting","--voice-save-preview","--episode-day-preview","--reduce-motion-preview"];app.launch()
  XCTAssertTrue(app.staticTexts["Waiting for the rest of your audio"].waitForExistence(timeout:10))
  XCTAssertTrue(app.staticTexts["Uploads resume while this app is open. Once all audio reaches your Mac, it can transcribe while the phone is away."].exists)
  XCTAssertFalse(app.buttons["voice.sendReviewed"].exists)
  XCTAssertFalse(app.textViews["voice.macDraft"].exists)
  capture("walk-waiting-upload-reduced-motion",app:app)
 }
 func testRecoveredReplyOffersExplicitPlaybackWithoutAutoplay() {
  continueAfterFailure=false
  let app=XCUIApplication();app.launchArguments=["--voice-evidence-preview","--voice-reply-media-preview","--tab","dialogue","--reduce-motion-preview"];app.launch()
  let replay=app.buttons["Play voice note"],read=app.buttons["Read reply aloud"]
  XCTAssertTrue(replay.waitForExistence(timeout:10));XCTAssertTrue(read.waitForExistence(timeout:10))
  XCTAssertGreaterThanOrEqual(read.frame.height,44);XCTAssertGreaterThanOrEqual(read.frame.width,44)
  XCTAssertEqual(read.label,"Read reply aloud") // SwiftUI combines the label's children for accessibility.
  capture("reply-original-audio-control",app:app)
  let list=app.scrollViews.firstMatch
  for _ in 0..<5 {
   if read.isHittable && read.frame.maxY <= list.frame.maxY && read.frame.minY >= list.frame.minY {break}
   list.swipeUp()
  }
  XCTAssertTrue(read.isHittable);XCTAssertLessThanOrEqual(read.frame.maxY,list.frame.maxY)
  XCTAssertGreaterThanOrEqual(read.frame.minY,list.frame.minY)
  capture("reply-explicit-recovery-reading",app:app)
  // Do not press either action: this is an inert visual check, not a media/provider request.
 }
}
''' )
env=dict(os.environ,DEVELOPER_DIR='/Applications/Xcode.app/Contents/Developer')
result=pathlib.Path(os.environ.get('ALICIA_TEST_EVIDENCE_DIR',str(work)))/'voice-mac-ui.xcresult'
only=os.environ.get('ALICIA_UI_TEST_FILTER')
filters=['-only-testing:ContextUITests/ContextUITests/'+only] if only else []
subprocess.run(['xcodebuild','-project',str(project),'-scheme','Alicia','-destination','platform=iOS Simulator,id=F36E7803-4EEE-47D1-8D8A-7C930515EB27','-derivedDataPath',str(work/'DerivedData'),'-resultBundlePath',str(result),'-parallel-testing-enabled','NO','CODE_SIGNING_ALLOWED=NO','test']+filters,env=env,check=True)
