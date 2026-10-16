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
