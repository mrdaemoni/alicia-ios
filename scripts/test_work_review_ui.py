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
final class WorkReviewUITests: XCTestCase {
 func capture(_ name:String,_ app:XCUIApplication) { let shot=XCTAttachment(screenshot:app.screenshot());shot.name=name;shot.lifetime = .keepAlways;add(shot) }
 func reveal(_ element:XCUIElement,_ app:XCUIApplication,up:Bool=true) {
  for _ in 0..<16 {
   let bottom = app.keyboards.firstMatch.exists ? app.keyboards.firstMatch.frame.minY - 10 : app.frame.maxY - 90
   if element.exists && element.isHittable && element.frame.midY > 100 && element.frame.maxY < bottom { return }
   let towardBottom = element.exists ? element.frame.midY > app.frame.midY : up
   if towardBottom { app.swipeUp() } else { app.swipeDown() }
  }
 }
 func revealGoal(_ element:XCUIElement,_ app:XCUIApplication,left:Bool=true) {
  let tabs = app.scrollViews["workReview.goalTabs"]
  for _ in 0..<8 { if element.isHittable && element.frame.midX > 20 && element.frame.midX < app.frame.maxX-20 {return};if left {tabs.swipeLeft()} else {tabs.swipeRight()} }
 }
 func launch(_ extra:[String]=[]) -> XCUIApplication {
  continueAfterFailure=false
  let app=XCUIApplication(); app.launchArguments=["--collaboration-preview","--work-review-preview","--tab","us"]+extra; app.launch()
  let open=app.buttons["collaboration.open"];XCTAssertTrue(open.waitForExistence(timeout:20));reveal(open,app);open.tap();XCTAssertTrue(app.navigationBars["Together"].waitForExistence(timeout:10)); return app
 }
 func openWork(_ app:XCUIApplication) {
  let result=app.buttons["collaboration.result.preview-goal-result"];reveal(result,app);XCTAssertTrue(result.isHittable);result.tap()
  XCTAssertTrue(app.buttons["workReview.agree.preview-q7"].waitForExistence(timeout:10))
 }
 func testSeparateAgreementImportanceAndGoals() {
  let app=launch();capture("goals-and-review-progress",app)
  let second=app.buttons["workReview.goal.preview-goal-two"];revealGoal(second,app);second.tap()
  XCTAssertFalse(app.buttons["collaboration.result.preview-goal-result"].exists)
  let all=app.buttons["workReview.goal.all"];revealGoal(all,app,left:false);all.tap();openWork(app)
  capture("q7-review-actions",app)
  let important=app.buttons["workReview.salient.preview-q7"];reveal(important,app);important.tap()
  XCTAssertTrue(app.staticTexts["Saved for Alicia's next revision."].waitForExistence(timeout:10))
  XCTAssertTrue(important.isSelected);XCTAssertFalse(app.buttons["workReview.agree.preview-q7"].isSelected)
  let agree=app.buttons["workReview.agree.preview-q7"];agree.tap();XCTAssertTrue(agree.isSelected)
  XCTAssertTrue(important.isSelected)
  let disagree=app.buttons["workReview.disagree.preview-q7"];disagree.tap();XCTAssertTrue(disagree.isSelected);XCTAssertFalse(agree.isSelected);XCTAssertTrue(important.isSelected)
  capture("independent-review-dimensions",app)
 }
 func testAnswerStaysInlineAndDraftSurvivesNavigation() {
  let app=launch(["--work-review-save-delay"]);openWork(app)
  let answer=app.buttons["workReview.answer.preview-q7"];reveal(answer,app);answer.tap()
  let field=app.textFields["workReview.editor.preview-q7"];reveal(field,app);field.tap()
  let words="Presence matters, but only after a real material floor. I disagree with treating attention as a replacement for resources. My example is the time I had enough tools but could not give the work sustained attention. Keep the scarcity counterexample alongside this."
  field.typeText(words);capture("answer-inline-keyboard",app)
  if app.buttons["Done writing"].exists {app.buttons["Done writing"].tap()}
  let keep=app.buttons["Keep draft"];reveal(keep,app);keep.tap()
  app.navigationBars.buttons.element(boundBy:0).tap();openWork(app)
  let restored=app.textFields["workReview.editor.preview-q7"];reveal(restored,app);XCTAssertEqual(restored.value as? String,words)
  let save=app.buttons["workReview.save.preview-q7"];reveal(save,app);save.tap()
  XCTAssertTrue(app.navigationBars["Prepared work"].exists);XCTAssertFalse(restored.isEnabled)
  capture("answer-save-pending-in-place",app)
  XCTAssertTrue(app.staticTexts["Your answer"].waitForExistence(timeout:15))
  let saved=app.staticTexts.matching(NSPredicate(format:"label == %@",words)).firstMatch;reveal(saved,app,up:false);XCTAssertTrue(saved.exists);capture("answer-saved-on-passage",app)
 }
 func testEditRestoreAndContextualDialogue() {
  let app=launch();openWork(app)
  let edit=app.buttons["workReview.edit.preview-q7"];reveal(edit,app);edit.tap()
  let field=app.textFields["workReview.editor.preview-q7"];reveal(field,app);field.tap();field.typeText(" My qualification: enough room to attend.")
  if app.buttons["Done writing"].exists {app.buttons["Done writing"].tap()}
  let save=app.buttons["workReview.save.preview-q7"];reveal(save,app);save.tap()
  XCTAssertTrue(app.staticTexts["Your edit"].waitForExistence(timeout:10))
  let discuss=app.buttons["workReview.discuss.preview-q7"];reveal(discuss,app);discuss.tap()
  let target=app.buttons["workReview.dialogueContext"];XCTAssertTrue(target.waitForExistence(timeout:10));capture("dialogue-exact-goal-context",app)
  let compose=app.textFields["dialogue.composer"];compose.tap();compose.typeText("How can we test that this week?")
  app.buttons["Send typed message"].tap()
  let response=app.staticTexts.matching(NSPredicate(format:"label BEGINSWITH %@","Preview · We are discussing")).firstMatch
  XCTAssertTrue(response.waitForExistence(timeout:15));capture("dialogue-context-response",app)
  target.tap();XCTAssertTrue(app.navigationBars["Prepared work"].waitForExistence(timeout:10))
 }
 func testSetAsideRestoresOriginalAndKeepsSignals() {
  let app=launch(["--collaboration-reduce-motion-preview"]);openWork(app)
  let agree=app.buttons["workReview.agree.preview-q7"];reveal(agree,app);agree.tap()
  let important=app.buttons["workReview.salient.preview-q7"];important.tap()
  let more=app.buttons["workReview.more.preview-q7"];reveal(more,app);more.tap();app.buttons["Set aside"].tap()
  let hidden=app.buttons["Set aside · 1"];reveal(hidden,app);XCTAssertTrue(hidden.exists);hidden.tap()
  let restore=app.buttons["Restore this piece"];reveal(restore,app);capture("set-aside-is-recoverable",app);restore.tap()
  reveal(agree,app,up:false);XCTAssertTrue(agree.isSelected);XCTAssertTrue(important.isSelected)
  capture("restored-original-and-feedback",app)
 }
 func testConnectionActionsAndStudioLink() {
  let app=launch();let connection=app.buttons["collaboration.connection.preview-connection"];reveal(connection,app);connection.tap()
  XCTAssertTrue(app.buttons["collaboration.use"].isHittable);XCTAssertTrue(app.buttons["collaboration.clarify"].isHittable);XCTAssertTrue(app.buttons["collaboration.dismiss"].isHittable)
  capture("connection-decisions-at-top",app)
  let evidence=app.buttons["Evidence and your words"];reveal(evidence,app);evidence.tap()
  let source=app.buttons["Preview · Sculpture and subtraction"];reveal(source,app);source.tap()
  let studio=app.buttons["workReview.openStudio"];reveal(studio,app);studio.tap()
  XCTAssertTrue(app.buttons["workReview.studioGoal.preview-goal"].waitForExistence(timeout:15));capture("studio-backlink-to-goal",app)
  let playing=app.buttons.matching(NSPredicate(format:"label == %@","Pause")).firstMatch;XCTAssertFalse(playing.exists)
 }
}
''')
env=dict(os.environ,DEVELOPER_DIR='/Applications/Xcode.app/Contents/Developer')
result=pathlib.Path(os.environ.get('ALICIA_TEST_EVIDENCE_DIR',str(work)))/('work-review-ui-'+work.name+'.xcresult')
selected=[name for name in os.environ.get('ALICIA_UI_TESTS','').split(',') if name]
filters=['-only-testing:ContextUITests/WorkReviewUITests/'+name for name in selected]
subprocess.run(['xcodebuild','-project',str(project),'-scheme','Alicia','-destination','platform=iOS Simulator,name=iPhone 17','-derivedDataPath',str(work/'DerivedData'),'-resultBundlePath',str(result),'-parallel-testing-enabled','NO','CODE_SIGNING_ALLOWED=NO','test']+filters,env=env,check=True)
