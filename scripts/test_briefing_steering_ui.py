"""Temporary XCUITest target for the steerable briefing (CL-20261015-steerable-briefing); no project-file change."""
import json, os, pathlib, plistlib, shutil, subprocess, tempfile
import xml.etree.ElementTree as ET
root = pathlib.Path(__file__).resolve().parents[1]
work = pathlib.Path(tempfile.mkdtemp(prefix='alicia-steer-ui-'))
print(work, flush=True)
project = work / 'Alicia.xcodeproj'
shutil.copytree(root / 'Alicia.xcodeproj', project)
for folder in ('Alicia','AliciaWidgets','Shared'):
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
(work/'ContextUITests/ContextUITests.swift').write_text(r"""
import XCTest
// Invented fixture only (--morning-briefing-steer-preview): no audio loads, nothing is sent.
final class BriefingSteeringUITests: XCTestCase {
 func launch(_ extra:[String]) -> XCUIApplication {
  continueAfterFailure=false
  let app=XCUIApplication();app.launchArguments=["--morning-briefing-steer-preview"]+extra;app.launch();return app
 }
 func capture(_ name:String,_ app:XCUIApplication) {let shot=XCTAttachment(screenshot:app.screenshot());shot.name=name;shot.lifetime = .keepAlways;add(shot)}
 func testDuringArmSteersWhilePlaying() {
  let app=launch(["--reading-bar-preview"])
  XCTAssertTrue(app.buttons["steer.higher"].waitForExistence(timeout:15))
  XCTAssertTrue(app.buttons["steer.lower"].exists);XCTAssertTrue(app.buttons["steer.again"].exists)
  XCTAssertTrue(app.staticTexts["steer.arm"].label.contains("STEER WHILE IT PLAYS"))
  XCTAssertFalse(app.buttons["steer.landed"].exists)
  capture("steer-during-bar",app)
  app.buttons["steer.higher"].tap()
  let line=app.staticTexts["steer.line"];XCTAssertTrue(line.waitForExistence(timeout:5))
  XCTAssertEqual(line.label,"From higher up, starting with the next sentence")
  capture("steer-during-interpretation",app)
 }
 func testLowerNamesItsLine() {
  let app=launch(["--reading-bar-preview"])
  XCTAssertTrue(app.buttons["steer.lower"].waitForExistence(timeout:15));app.buttons["steer.lower"].tap()
  XCTAssertTrue(app.staticTexts["steer.line"].waitForExistence(timeout:5))
  XCTAssertEqual(app.staticTexts["steer.line"].label,"Closer in, starting with the next sentence")
 }
 func testDuringArmEndShowsOnlyTheCheck() {
  let app=launch(["--reading-bar-preview","--steer-ended-preview"])
  XCTAssertTrue(app.buttons["steer.landed"].waitForExistence(timeout:15))
  XCTAssertTrue(app.buttons["steer.didntLand"].exists)
  XCTAssertFalse(app.buttons["steer.higher"].exists,"During weeks: no steering after the end")
  capture("steer-during-end-check",app)
  app.buttons["steer.landed"].tap()
  XCTAssertTrue(app.staticTexts["steer.verdictNotice"].waitForExistence(timeout:5))
  XCTAssertTrue(app.buttons["steer.landed"].isSelected)
 }
 func testAfterArmHidesControlsUntilTheEnd() {
  let app=launch(["--reading-bar-preview","--steer-after-arm"])
  XCTAssertTrue(app.staticTexts["steer.arm"].waitForExistence(timeout:15))
  XCTAssertTrue(app.staticTexts["steer.arm"].label.contains("STEER WHEN IT ENDS"))
  XCTAssertFalse(app.buttons["steer.higher"].exists,"After weeks: nothing to press while it plays")
  capture("steer-after-playing",app)
 }
 func testAfterArmEndOffersTheSameControls() {
  let app=launch(["--reading-bar-preview","--steer-after-arm","--steer-ended-preview"])
  XCTAssertTrue(app.buttons["steer.higher"].waitForExistence(timeout:15))
  XCTAssertTrue(app.buttons["steer.landed"].exists)
  capture("steer-after-end",app)
  app.buttons["steer.higher"].tap()
  XCTAssertTrue(app.staticTexts["steer.line"].waitForExistence(timeout:5))
  XCTAssertEqual(app.staticTexts["steer.line"].label,"The whole briefing again, from higher up")
  capture("steer-after-replay-line",app)
 }
 func testImmersiveReaderCarriesTheControls() {
  let app=launch(["--immersive-reading-preview"])
  XCTAssertTrue(app.buttons["reading.play"].waitForExistence(timeout:15))
  XCTAssertTrue(app.buttons["steer.higher"].exists)
  XCTAssertTrue(app.staticTexts["Tap a word to listen from there."].exists)
  capture("steer-immersive-reader",app)
 }
 func testBriefingCardOffersHeadphoneSteeringOffByDefault() {
  let app=launch(["--tab","us"])
  let disclosure=app.buttons["Steering this briefing"]
  XCTAssertTrue(disclosure.waitForExistence(timeout:20));disclosure.tap()
  let toggle=app.buttons["morningBriefing.remoteSteering"];XCTAssertTrue(toggle.waitForExistence(timeout:5))
  XCTAssertEqual(toggle.value as? String,"Off")
  capture("steer-card-settings",app)
  toggle.tap();XCTAssertEqual(toggle.value as? String,"On");toggle.tap()
 }
 // Live local playback (--steer-live-audio): the real SpeechReader plays tone
 // files placed at the fixture's word times, so seams are observed, not reasoned.
 func pathContains(_ path:XCUIElement,_ text:String,_ timeout:TimeInterval) -> Bool {
  let end=Date().addingTimeInterval(timeout)
  while Date()<end { if path.exists && path.label.contains(text) { return true }; usleep(200_000) }
  return false
 }
 func waitEnabled(_ e:XCUIElement,_ enabled:Bool,_ t:TimeInterval) -> Bool {
  let p=NSPredicate(format:"isEnabled == %@",NSNumber(value:enabled))
  return XCTWaiter().wait(for:[expectation(for:p,evaluatedWith:e)],timeout:t) == .completed
 }
 func startLive() -> (XCUIApplication, XCUIElement) {
  let app=launch(["--steer-live-audio","--tab","us"])
  let play=app.buttons["morningBriefing.play"];XCTAssertTrue(play.waitForExistence(timeout:20));play.tap()
  XCTAssertTrue(app.buttons["briefingStage.close"].waitForExistence(timeout:10),"Starting the briefing opens the full-screen room")
  let path=app.staticTexts["steer.debug.path"];XCTAssertTrue(path.waitForExistence(timeout:10))
  XCTAssertTrue(pathContains(path,"s01·0·0",10),"Playback begins with s01 at L0")
  return (app,path)
 }
 func testLiveHigherChangesOnlyTheRemainder() {
  let (app,path)=startLive()
  sleep(3)   // inside s01's first sentence (fixture 1.8–6.25 s)
  app.buttons["steer.higher"].tap()
  XCTAssertTrue(app.staticTexts["steer.line"].waitForExistence(timeout:5))
  XCTAssertTrue(pathContains(path,"s01·0·0 > s01·1·1",15),"After the sentence, L+1 resumes at its unheard caveat: \(path.label)")
  capture("steer-live-after-higher",app)
  // At the top, Higher would change nothing: it is faded and can't be pressed (Hector, 2026-10-17).
  XCTAssertTrue(waitEnabled(app.buttons["steer.higher"],false,5),"Hearing L+1: Higher is faded")
  XCTAssertTrue(app.buttons["steer.lower"].isEnabled && app.buttons["steer.again"].isEnabled,"Lower and Again stay open")
  capture("steer-live-higher-faded",app)
  XCTAssertTrue(pathContains(path,"s02·1·0",25),"Later segments follow the new level: \(path.label)")
  XCTAssertFalse(app.staticTexts["reading.failure"].exists)
  // The L0 piece was cut after its first sentence (~6.4 s of a ~10.3 s chunk), not played whole.
  let heard=app.staticTexts["steer.debug.seconds"].label.split(separator:" ").compactMap{Double($0)}
  XCTAssertTrue(heard.count>=2 && heard[0]>3.5 && heard[0]<8.0,"First stretch was cut at the boundary: \(heard)")
 }
 func testLiveAgainReplaysTheSentence() {
  let (app,path)=startLive()
  sleep(4)   // well into s01's first sentence
  app.buttons["steer.again"].tap()
  XCTAssertTrue(pathContains(path,"s01·0·0 > s01·0·0",10),"Again starts the same sentence once more: \(path.label)")
  XCTAssertTrue(pathContains(path,"s02·0·0",30),"Then the briefing continues at L0: \(path.label)")
  XCTAssertFalse(app.staticTexts["reading.failure"].exists)
 }
 // The briefing as a room (Hector, 2026-10-17): her field, no text, the same controls, the screen held awake.
 func testBriefingStageIsTheBriefingRoom() {
  let app=launch(["--briefing-stage-preview"])
  XCTAssertTrue(app.buttons["steer.higher"].waitForExistence(timeout:15))
  XCTAssertTrue(app.buttons["steer.lower"].exists && app.buttons["steer.again"].exists)
  XCTAssertTrue(app.buttons["briefingStage.play"].exists && app.buttons["briefingStage.close"].exists)
  XCTAssertTrue(app.staticTexts["steer.arm"].label.contains("STEER WHILE IT PLAYS"))
  XCTAssertFalse(app.staticTexts["Tap a word to listen from there."].exists,"No text readout in the room")
  XCTAssertEqual(app.staticTexts["briefingStage.debug.awake"].label,"awake","The screen is held awake")
  capture("briefing-stage",app)
 }
 func testBriefingStageEndsWithTheCheck() {
  let app=launch(["--briefing-stage-preview","--steer-ended-preview"])
  XCTAssertTrue(app.buttons["steer.landed"].waitForExistence(timeout:15))
  XCTAssertFalse(app.buttons["steer.higher"].exists,"During weeks: no steering after the end")
  capture("briefing-stage-end",app)
 }
 func testLiveStageBreathesWithHerWordsAndReopensFromTheBar() {
  let (app,_)=startLive()
  let level=app.staticTexts["briefingStage.debug.level"];XCTAssertTrue(level.waitForExistence(timeout:5))
  var seen:[Double]=[]
  for _ in 0..<16 { if let v=Double(level.label) { seen.append(v) }; usleep(180_000) }
  XCTAssertTrue(Set(seen).count>=3 && (seen.max() ?? 0)>0.6 && (seen.min() ?? 1)<0.45,"Her breath follows her words: \(seen)")
  XCTAssertEqual(app.staticTexts["briefingStage.debug.awake"].label,"awake","The screen is held awake while she reads")
  capture("briefing-stage-live",app)
  app.buttons["briefingStage.close"].tap()
  let open=app.buttons["reading.open"];XCTAssertTrue(open.waitForExistence(timeout:5),"Closing leaves her reading in the bar")
  XCTAssertTrue(open.label.contains("FULL SCREEN"))
  XCTAssertTrue(app.staticTexts["steer.debug.path"].exists,"Playback continues after closing the room")
  open.tap()
  XCTAssertTrue(app.buttons["briefingStage.close"].waitForExistence(timeout:5),"The bar opens the room again")
 }
 func testLargeTypeKeepsTheControls() {
  let app=XCUIApplication();app.launchArguments=["--morning-briefing-steer-preview","--reading-bar-preview",
   "-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryAccessibilityXXXL"];app.launch()
  XCTAssertTrue(app.buttons["steer.higher"].waitForExistence(timeout:15))
  capture("steer-large-type",app)
 }
}
""")
env=dict(os.environ,DEVELOPER_DIR='/Applications/Xcode.app/Contents/Developer')
evidence=pathlib.Path(os.environ.get('ALICIA_TEST_EVIDENCE_DIR',str(work)))
result=evidence/('steer-ui-'+work.name+'.xcresult')
subprocess.run(['xcodebuild','-project',str(project),'-scheme','Alicia','-destination','platform=iOS Simulator,name=iPhone 17','-derivedDataPath',str(work/'DerivedData'),'-resultBundlePath',str(result),'-parallel-testing-enabled','NO','CODE_SIGNING_ALLOWED=NO','test'],env=env,check=True)
# Export the screenshots for review and public use (invented fixture only).
shots=evidence/'steer-screenshots';shots.mkdir(exist_ok=True)
subprocess.run(['xcrun','xcresulttool','export','attachments','--path',str(result),'--output-path',str(shots)],env=env,check=False)
print('screenshots:',shots)
