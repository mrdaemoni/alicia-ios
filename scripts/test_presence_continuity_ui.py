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

/// A2-052 — she walks through every room, including Body and the microphone.
final class PresenceContinuityUITests: XCTestCase {
 func capture(_ name:String,_ app:XCUIApplication) {
  let shot=XCTAttachment(screenshot:app.screenshot());shot.name=name;shot.lifetime = .keepAlways;add(shot)
 }
 func launch(_ tab:String,_ extra:[String]=[]) -> XCUIApplication {
  continueAfterFailure=false
  let app=XCUIApplication()
  app.launchArguments=["--reset-drafts","--body-preview","--episode-day-preview","--tab",tab]+extra
  app.launch()
  XCTAssertTrue(app.buttons["US"].waitForExistence(timeout:15));return app
 }
 /// The middle third of the screen as raw pixels: below the title, above the
 /// band, where only her field changes on its own.
 func band(_ app:XCUIApplication) -> [UInt8] {
  let image=app.screenshot().image.cgImage!
  let crop=image.cropping(to:CGRect(x:0,y:image.height/3,width:image.width,height:image.height/3))!
  return [UInt8]((crop.dataProvider!.data! as Data))
 }
 /// Codex review of #45: the briefing playlist opens inside Us but drew a
 /// Studio background, and a surface that is not the selected tab froze her.
 /// She must move on the pushed page (two frames differ), and BACK must
 /// return to Us, not to Studio.
 func testUsPlaylistKeepsHerMovingAndBackReturnsHome() {
  let app=launch("us",["--morning-briefing-preview"])
  let open=app.buttons["morningBriefing.playlist"]
  XCTAssertTrue(open.waitForExistence(timeout:15))
  XCTAssertFalse(open.label.contains("Studio"),"the label still says it opens in Studio: \(open.label)")
  open.tap()
  let back=app.buttons["BACK"]
  XCTAssertTrue(back.waitForExistence(timeout:10))
  sleep(2)
  let first=band(app)
  Thread.sleep(forTimeInterval:1.5)
  let second=band(app)
  let changed=zip(first,second).filter { $0 != $1 }.count
  XCTAssertGreaterThan(changed,2_000,"her field did not move on the pushed playlist (\(changed) bytes changed)")
  capture("us-playlist-moving",app)
  back.tap()
  XCTAssertTrue(app.buttons["morningBriefing.playlist"].waitForExistence(timeout:10),"BACK did not return to Us")
  XCTAssertTrue(app.buttons["us.openArc"].exists)
 }
 /// "The body section should look very similar to the other section."
 func testEveryRoomCarriesHer() {
  let app=launch("us")
  for name in ["US","MIND","BODY","ALICIA","STUDIO"] {
   app.buttons[name].tap()
   XCTAssertTrue(app.textFields["conversation.fieldInline"].waitForExistence(timeout:10))
   capture("room-"+name,app)
  }
 }
 /// "That same animation should appear when I open the microphone."
 func testTheMicrophoneIsTheSameRoom() {
  let app=launch("body",["--episode-microphone-on"])
  capture("body-with-her-behind-it",app)
  app.buttons["composer.walk"].tap()
  XCTAssertTrue(app.descendants(matching:.any)["listening.presence"].waitForExistence(timeout:15))
  let state=app.descendants(matching:.any).matching(identifier:"walk.microphoneState").firstMatch
  XCTAssertTrue(state.label.contains("Alicia is listening"),"microphone state is not explicit beside her field: \(state.label)")
  capture("microphone-same-field",app)
 }
 /// Reduce Motion must remain still even while the microphone amplitude
 /// changes. The DEBUG fixture alternates between quiet and loud levels; two
 /// middle-field captures must therefore be pixel-identical.
 func testReduceMotionIgnoresChangingMicrophoneLevel() {
  let app=launch("body",["--episode-microphone-on","--reduce-motion-preview","--changing-voice-level-preview"])
  app.buttons["composer.walk"].tap()
  XCTAssertTrue(app.descendants(matching:.any)["listening.presence"].waitForExistence(timeout:15))
  sleep(1)
  let first=band(app)
  Thread.sleep(forTimeInterval:1.5)
  let second=band(app)
  let changed=zip(first,second).filter { $0 != $1 }.count
  XCTAssertEqual(changed,0,"Reduce Motion changed while microphone amplitude moved (\(changed) bytes)")
  capture("microphone-reduce-motion-still",app)
 }
}
""")

env=dict(os.environ,DEVELOPER_DIR='/Applications/Xcode.app/Contents/Developer')
result=pathlib.Path(os.environ.get('ALICIA_TEST_EVIDENCE_DIR',str(work)))/('presence-continuity-'+work.name+'.xcresult')
selected=[name for name in os.environ.get('ALICIA_UI_TESTS','').split(',') if name]
filters=['-only-testing:ContextUITests/PresenceContinuityUITests/'+name for name in selected]
subprocess.run(['xcodebuild','-project',str(project),'-scheme','Alicia','-destination','platform=iOS Simulator,name=iPhone 17','-derivedDataPath',str(work/'DerivedData'),'-resultBundlePath',str(result),'-parallel-testing-enabled','NO','CODE_SIGNING_ALLOWED=NO','test']+filters,env=env,check=True)
