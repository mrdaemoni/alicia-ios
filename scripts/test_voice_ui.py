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
  for _ in 0..<12 {if element.isHittable{return};if up {app.swipeUp()} else {app.swipeDown()}}
 }
 func testOriginalVoiceReviewCorrectionAndDelete() {
  continueAfterFailure=false
  let app=XCUIApplication();app.launchArguments=["--voice-evidence-preview","--tab","dialogue"];app.launch()
  let archive=app.buttons["voice.recordings"]
  XCTAssertTrue(archive.waitForExistence(timeout:10));archive.tap()
  let row=app.buttons.matching(NSPredicate(format:"label CONTAINS %@","Preview · Endings Chosen")).firstMatch
  XCTAssertTrue(row.waitForExistence(timeout:10));row.tap()
  let play=app.buttons["voice.playOriginal"]
  XCTAssertTrue(play.waitForExistence(timeout:10));reveal(play,app:app)
  XCTAssertTrue(play.isHittable);play.tap()
  XCTAssertTrue(app.buttons["STOP PLAYBACK"].waitForExistence(timeout:10))
  app.buttons["STOP PLAYBACK"].tap()
  capture("original-voice-context",app:app)
  let editor=app.textViews["Corrected transcript"]
  reveal(editor,app:app);XCTAssertTrue(editor.isHittable);editor.tap();editor.typeText("Preview correction: I meant a criterion for continuing.")
  XCTAssertTrue((editor.value as? String ?? "").contains("criterion for continuing"))
  capture("voice-correction-with-keyboard",app:app)
  let save=app.buttons["SAVE CORRECTION"];reveal(save,app:app);XCTAssertTrue(save.isHittable);save.tap()
  XCTAssertTrue(app.staticTexts["Correction kept. Sync status shows whether it reached Alicia."].waitForExistence(timeout:10))
  let delete=app.buttons["DELETE AUDIO"];reveal(delete,app:app,up:false);XCTAssertTrue(delete.isHittable);delete.tap()
  let confirm=app.buttons["Delete original audio"];XCTAssertTrue(confirm.waitForExistence(timeout:5));confirm.tap()
  XCTAssertTrue(app.staticTexts["Audio deleted on this phone. Deletion on the Mac is pending; tap Sync."].waitForExistence(timeout:10))
  capture("original-audio-deleted-words-kept",app:app)
 }
}
''')
env=dict(os.environ,DEVELOPER_DIR='/Applications/Xcode.app/Contents/Developer')
result=pathlib.Path(os.environ.get('ALICIA_TEST_EVIDENCE_DIR',str(work)))/'voice-ui.xcresult'
subprocess.run(['xcodebuild','-project',str(project),'-scheme','Alicia','-destination','platform=iOS Simulator,id=F36E7803-4EEE-47D1-8D8A-7C930515EB27','-derivedDataPath',str(work/'DerivedData'),'-resultBundlePath',str(result),'-parallel-testing-enabled','NO','CODE_SIGNING_ALLOWED=NO','test'],env=env,check=True)
