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
 func capture(_ name:String,app:XCUIApplication){let shot=XCTAttachment(screenshot:app.screenshot());shot.name=name;shot.lifetime = .keepAlways;add(shot)}
 func reveal(_ el:XCUIElement,app:XCUIApplication,up:Bool=true){for _ in 0..<15 {if el.isHittable{return};if up{app.swipeUp()}else{app.swipeDown()}}}
 func launch(_ args:[String]=[])->XCUIApplication {continueAfterFailure=false;let app=XCUIApplication();app.launchArguments=["--collaboration-preview","--tab","us"]+args;app.launch();return app}
 func testUseClarifyCommitAndOutcome(){
  let app=launch();let open=app.buttons["collaboration.open"];XCTAssertTrue(open.waitForExistence(timeout:15));capture("shared-focus-without-playback",app:app);open.tap()
  let connection=app.buttons["collaboration.connection.preview-connection"];XCTAssertTrue(connection.waitForExistence(timeout:10));reveal(connection,app:app);connection.tap()
  let use=app.buttons["collaboration.use"];reveal(use,app:app);use.tap();XCTAssertTrue(app.staticTexts["Saved."].waitForExistence(timeout:10))
  let clarify=app.buttons["collaboration.clarify"];reveal(clarify,app:app);clarify.tap()
  let question=app.staticTexts["Preview clarification · Which outcome would make this removal worthwhile?"];reveal(question,app:app,up:false);XCTAssertTrue(question.exists);capture("connection-clarified",app:app)
  let commit=app.buttons["collaboration.commitEditor"];reveal(commit,app:app);commit.tap()
  let action=app.textFields["collaboration.field.What will happen?"];XCTAssertTrue(action.waitForExistence(timeout:10));action.tap();action.typeText(" Start with the studio.")
  let done=app.buttons["Done writing"];if done.exists{done.tap()}
  let confirm=app.buttons["collaboration.confirmCommit"];reveal(confirm,app:app);capture("editable-explicit-agreement",app:app);confirm.tap()
  XCTAssertTrue(app.navigationBars["The connection"].waitForExistence(timeout:10));app.navigationBars.buttons.element(boundBy:0).tap()
  let agreement=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","collaboration.agreement.")).firstMatch;reveal(agreement,app:app);XCTAssertTrue(agreement.exists);agreement.tap()
  XCTAssertTrue(app.staticTexts["Prepared by Alicia · awaiting your review"].waitForExistence(timeout:10));capture("prepared-work-is-not-outcome",app:app)
  let update=app.buttons["collaboration.outcomeEditor"];reveal(update,app:app,up:false);update.tap()
  let report=app.textFields["collaboration.field.In your words"];XCTAssertTrue(report.waitForExistence(timeout:10));report.tap();report.typeText("Preview: the comparison made my criterion clearer.")
  if app.buttons["Done writing"].exists{app.buttons["Done writing"].tap()}
  app.buttons["Record an observation"].tap()
  XCTAssertTrue(app.staticTexts["Preview: the comparison made my criterion clearer."].waitForExistence(timeout:10));capture("explicit-outcome",app:app)
 }
 func testGoalAndEvidence(){
  let app=launch();let open=app.buttons["collaboration.open"];XCTAssertTrue(open.waitForExistence(timeout:15));open.tap()
  let goal=app.buttons["collaboration.newGoal"];reveal(goal,app:app);goal.tap()
  for (label,text) in [("Title","Preview goal"),("What would a useful outcome look like?","A clear decision"),("Why does it matter?","To focus my attention")]{let field=app.textFields["collaboration.field."+label];reveal(field,app:app);field.tap();field.typeText(text)}
  if app.buttons["Done writing"].exists{app.buttons["Done writing"].tap()}
  capture("goal-editor",app:app);let save=app.buttons["collaboration.saveGoal"];reveal(save,app:app);save.tap()
  XCTAssertTrue(app.staticTexts["Preview goal"].waitForExistence(timeout:10))
  let connection=app.buttons["collaboration.connection.preview-connection"];reveal(connection,app:app);connection.tap()
  let evidence=app.buttons["Evidence and your words"];reveal(evidence,app:app);evidence.tap()
  let source=app.buttons["Preview · Sculpture and subtraction"];reveal(source,app:app);source.tap();app.buttons["Open current source"].tap()
  XCTAssertTrue(app.staticTexts["Fixture source. No live file was read."].waitForExistence(timeout:10));capture("captured-and-current-evidence",app:app)
  app.navigationBars.buttons.element(boundBy:0).tap()
  let voice=app.buttons["Preview · Your recorded question"];reveal(voice,app:app);voice.tap();app.buttons["Review original voice"].tap()
  XCTAssertTrue(app.buttons["voice.playOriginal"].waitForExistence(timeout:10));capture("original-voice-drilldown",app:app)
 }
 func testQuietSettingsAndReduceMotion(){
  let app=launch(["--collaboration-reduce-motion-preview"]);let open=app.buttons["collaboration.open"];XCTAssertTrue(open.waitForExistence(timeout:15));capture("shared-focus-reduce-motion",app:app);open.tap()
  let settings=app.buttons["When Alicia returns"];reveal(settings,app:app);settings.tap()
  let stop=app.buttons["collaboration.stop"];reveal(stop,app:app);stop.tap()
  XCTAssertTrue(app.staticTexts["Stopped on this phone. Any pending server change stays queued below."].waitForExistence(timeout:10));capture("stop-purposeful-returns",app:app)
 }
 func testExactTarget(){let app=launch(["--collaboration-target-preview"]);XCTAssertTrue(app.navigationBars["The connection"].waitForExistence(timeout:20));capture("exact-notification-target",app:app)}
 func testDirectGoalWork(){let app=launch();let open=app.buttons["collaboration.open"];XCTAssertTrue(open.waitForExistence(timeout:15));open.tap();let work=app.buttons["collaboration.result.preview-goal-result"];XCTAssertTrue(work.waitForExistence(timeout:10));reveal(work,app:app);work.tap();XCTAssertTrue(app.staticTexts["Prepared toward your saved goal. This is work to inspect, not an agreed action or a verified outcome."].waitForExistence(timeout:10));capture("prepared-toward-goal-without-agreement",app:app)}
 func testContextPendingKeepsExactWords(){
  let app=launch(["--collaboration-save-delay-preview"]);let open=app.buttons["collaboration.open"];XCTAssertTrue(open.waitForExistence(timeout:15));open.tap()
  let context=app.buttons["Your context right now"];reveal(context,app:app);context.tap()
  let field=app.textFields["collaboration.signal"];reveal(field,app:app);field.tap();field.typeText("Preview context awaiting confirmation")
  let save=app.buttons["Save my context"];reveal(save,app:app);save.tap()
  XCTAssertFalse(field.isEnabled);XCTAssertEqual(field.value as? String,"Preview context awaiting confirmation");capture("context-draft-locked-during-save",app:app)
  XCTAssertTrue(app.staticTexts["Saved."].waitForExistence(timeout:15));XCTAssertTrue(field.isEnabled)
  XCTAssertEqual(field.value as? String,"What should she know now?")
 }
}
''')
env=dict(os.environ,DEVELOPER_DIR='/Applications/Xcode.app/Contents/Developer')
result=pathlib.Path(os.environ.get('ALICIA_TEST_EVIDENCE_DIR',str(work)))/('collaboration-ui-'+work.name+'.xcresult')
subprocess.run(['xcodebuild','-project',str(project),'-scheme','Alicia','-destination','platform=iOS Simulator,id=F36E7803-4EEE-47D1-8D8A-7C930515EB27','-derivedDataPath',str(work/'DerivedData'),'-resultBundlePath',str(result),'-parallel-testing-enabled','NO','CODE_SIGNING_ALLOWED=NO','test'],env=env,check=True)
