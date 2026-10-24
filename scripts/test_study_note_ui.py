"""Temporary XCUITest target for the study note card (CL-20261023-study-note-card); no project-file change."""
import json, os, pathlib, plistlib, shutil, subprocess, tempfile
import xml.etree.ElementTree as ET
root = pathlib.Path(__file__).resolve().parents[1]
work = pathlib.Path(tempfile.mkdtemp(prefix='alicia-study-note-ui-'))
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
// Invented fixture only (--study-note-preview): nothing is sent.
final class StudyNoteUITests: XCTestCase {
 func launch(_ extra:[String]) -> XCUIApplication {
  continueAfterFailure=false
  let app=XCUIApplication();app.launchArguments=["--study-note-preview","--tab","us"]+extra;app.launch();return app
 }
 func capture(_ name:String,_ app:XCUIApplication) {let shot=XCTAttachment(screenshot:app.screenshot());shot.name=name;shot.lifetime = .keepAlways;add(shot)}
 func testTheCardOpensTheTemplateAndSaves() {
  let app=launch([])
  let card=app.buttons["studyNote.card"];XCTAssertTrue(card.waitForExistence(timeout:15))
  XCTAssertTrue(card.label.contains("Week 2"))
  capture("study-note-card",app)
  card.tap()
  let field=app.textFields["studyNote.field.cost"].exists ? app.textFields["studyNote.field.cost"] : app.textViews["studyNote.field.cost"]
  XCTAssertTrue(field.waitForExistence(timeout:5))
  for id in ["mornings","not_steered","steered","landed","wrong","else"] {
   XCTAssertTrue(app.textFields["studyNote.field."+id].exists || app.textViews["studyNote.field."+id].exists, id)
  }
  field.tap();field.typeText("Invented answer for the fixture.")
  capture("study-note-sheet",app)
  app.buttons["studyNote.save"].tap()
  XCTAssertTrue(card.waitForExistence(timeout:5))
  let saved=NSPredicate(format:"label CONTAINS 'saved'")
  XCTAssertEqual(XCTWaiter().wait(for:[expectation(for:saved,evaluatedWith:card)],timeout:5), .completed, "The card says it is saved")
  XCTAssertFalse(card.isEnabled,"A saved card stays for the day and opens nothing")
  capture("study-note-saved",app)
 }
 func testAFailedSaveKeepsTheWordsAndSaysSo() {
  let app=launch(["--study-note-fail-once"])
  let card=app.buttons["studyNote.card"];XCTAssertTrue(card.waitForExistence(timeout:15));card.tap()
  let field=app.textFields["studyNote.field.cost"].exists ? app.textFields["studyNote.field.cost"] : app.textViews["studyNote.field.cost"]
  XCTAssertTrue(field.waitForExistence(timeout:5));field.tap();field.typeText("Kept on the phone.")
  app.buttons["studyNote.save"].tap()
  XCTAssertTrue(app.staticTexts["studyNote.notice"].waitForExistence(timeout:5))
  XCTAssertTrue((field.value as? String ?? "").contains("Kept on the phone."),"The words stay after a failed save")
  capture("study-note-retry",app)
  app.buttons["studyNote.save"].tap()
  XCTAssertTrue(card.waitForExistence(timeout:5))
 }
}
""")
env=dict(os.environ,DEVELOPER_DIR='/Applications/Xcode.app/Contents/Developer')
evidence=pathlib.Path(os.environ.get('ALICIA_TEST_EVIDENCE_DIR',str(work)))
result=evidence/('study-note-ui-'+work.name+'.xcresult')
subprocess.run(['xcodebuild','-project',str(project),'-scheme','Alicia','-destination','platform=iOS Simulator,name=iPhone 17','-derivedDataPath',str(work/'DerivedData'),'-resultBundlePath',str(result),'-parallel-testing-enabled','NO','CODE_SIGNING_ALLOWED=NO','test'],env=env,check=True)
# Export the screenshots for review and public use (invented fixture only).
shots=evidence/'study-note-screenshots';shots.mkdir(exist_ok=True)
subprocess.run(['xcrun','xcresulttool','export','attachments','--path',str(result),'--output-path',str(shots)],env=env,check=False)
print('screenshots:',shots)
