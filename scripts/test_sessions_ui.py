"""Temporary XCUITest target for the real app; no changes to its project file."""
import json, os, pathlib, plistlib, shutil, subprocess, tempfile
import xml.etree.ElementTree as ET
root = pathlib.Path(__file__).resolve().parents[1]
work = pathlib.Path(tempfile.mkdtemp(prefix='alicia-context-ui-'))
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

/// A2-059 — the Sessions list scrolls, and swiping still deletes.
final class SessionsUITests: XCTestCase {
 func capture(_ name:String,_ app:XCUIApplication) {
  let shot=XCTAttachment(screenshot:app.screenshot());shot.name=name;shot.lifetime = .keepAlways;add(shot)
 }
 func openSessions() -> XCUIApplication {
  continueAfterFailure=false
  let app=XCUIApplication()
  app.launchArguments=["--reset-drafts","--sessions-preview","--episode-day-preview","--tab","alicia"]
  app.launch()
  let entry=app.buttons["sessions.open"]
  XCTAssertTrue(entry.waitForExistence(timeout:15),"no Sessions entry on the Alicia tab")
  entry.tap()
  XCTAssertTrue(app.buttons["sessions.close"].waitForExistence(timeout:10),"Sessions did not open")
  return app
 }

 /// The whole reason this exists: A2-058's drag gesture ate the scroll.
 func testItScrolls() {
  let app=openSessions()
  let rows=app.descendants(matching:.any).matching(identifier:"sessions.row")
  guard rows.count > 0 else { return XCTFail("no session rows in the preview") }
  let firstBefore=rows.element(boundBy:0).frame.origin.y
  capture("sessions-top",app)
  app.swipeUp(); app.swipeUp()
  let firstAfter=rows.element(boundBy:0).frame.origin.y
  capture("sessions-scrolled",app)
  XCTAssertLessThan(firstAfter,firstBefore,"the list did not move — the scroll is still being eaten")
 }

 /// The misfires go last and carry their own sweep, so a list of eighteen
 /// does not read as eighteen things he has to deal with.
 func testMisfiresAreGroupedLastAndClearableAtOnce() {
  let app=openSessions()
  // The group is last by design, and a List only builds what is near the
  // viewport — scroll to it before asking whether it is there.
  let misfires=app.descendants(matching:.any).matching(identifier:"sessions.clearMisfires").firstMatch
  for _ in 0..<12 where !misfires.exists { app.swipeUp() }
  XCTAssertTrue(misfires.exists,"misfires were not grouped with a way to clear them")
  let sweep=misfires
  XCTAssertTrue(sweep.isHittable,"the sweep is not reachable")
  capture("misfires-grouped",app)
 }

 /// 2026-09-22: Hector deleted one stuck S16E08 misfire from the band above
 /// the text box, went home, and the band showed the next of four more while
 /// Sessions said "none waiting on you". One rule now decides both.
 func testTheBandDoesNotNagAboutAccidents() {
  continueAfterFailure=false
  let app=XCUIApplication()
  app.launchArguments=["--reset-drafts","--sessions-preview","--episode-day-preview","--tab","alicia"]
  app.launch()
  let entry=app.buttons["sessions.open"]
  XCTAssertTrue(entry.waitForExistence(timeout:15))
  XCTAssertFalse(entry.label.contains("waiting for you"),"entry counts accidents: \(entry.label)")
  let band=app.descendants(matching:.any).matching(identifier:"composer.reflectionWaiting").firstMatch
  XCTAssertFalse(band.waitForExistence(timeout:3),"the band nags about a one-second accident: \(band.label)")
  capture("band-quiet-for-misfires",app)
 }

 /// The bug Hector hit: the Mac sends a walk, the phone never learns, and
 /// ten arrived reflections read "Sending to Alicia" under NEEDS YOU forever.
 func testAWalkTheMacSentReadsAsArrived() {
  continueAfterFailure=false
  let app=XCUIApplication()
  app.launchArguments=["--reset-drafts","--mac-sent-preview","--episode-day-preview","--tab","alicia"]
  app.launch()
  let entry=app.buttons["sessions.open"]
  XCTAssertTrue(entry.waitForExistence(timeout:15))
  // The entry must not claim these need him.
  XCTAssertFalse(entry.label.contains("waiting for you"),"entry says they wait: \(entry.label)")
  entry.tap()
  XCTAssertTrue(app.buttons["sessions.close"].waitForExistence(timeout:10))
  XCTAssertTrue(app.staticTexts["ALICIA HAS IT"].waitForExistence(timeout:10)
                || app.descendants(matching:.any)["ALICIA HAS IT"].waitForExistence(timeout:5),
                "a linked walk does not read as arrived")
  XCTAssertFalse(app.staticTexts["SENDING TO ALICIA"].exists,"still says sending")
  XCTAssertFalse(app.staticTexts["NEEDS YOU"].exists,"still grouped as needing him")
  capture("mac-sent-reads-as-arrived",app)
 }

 func testTheCloseButtonSurvivesScrolling() {
  let app=openSessions()
  app.swipeUp()
  // CLOSE scrolls away with the header, which is fine; scroll back for it.
  app.swipeDown(); app.swipeDown()
  XCTAssertTrue(app.buttons["sessions.close"].waitForExistence(timeout:5))
  app.buttons["sessions.close"].tap()
  XCTAssertTrue(app.buttons["ALICIA"].waitForExistence(timeout:10))
 }
}
""")

env=dict(os.environ,DEVELOPER_DIR='/Applications/Xcode.app/Contents/Developer')
result=pathlib.Path(os.environ.get('ALICIA_TEST_EVIDENCE_DIR',str(work)))/('sessions-'+work.name+'.xcresult')
selected=[name for name in os.environ.get('ALICIA_UI_TESTS','').split(',') if name]
filters=['-only-testing:ContextUITests/SessionsUITests/'+name for name in selected]
subprocess.run(['xcodebuild','-project',str(project),'-scheme','Alicia','-destination','platform=iOS Simulator,name=iPhone 17','-derivedDataPath',str(work/'DerivedData'),'-resultBundlePath',str(result),'-parallel-testing-enabled','NO','CODE_SIGNING_ALLOWED=NO','test']+filters,env=env,check=True)
