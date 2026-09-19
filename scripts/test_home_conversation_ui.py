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

/// A2-047 — Hector's build-18 field report about the home screen.
final class HomeConversationUITests: XCTestCase {
 func launch(_ tab:String="us",_ extra:[String]=[]) -> XCUIApplication {
  continueAfterFailure=false
  let app=XCUIApplication()
  // Drafts are durable across launches by design, so each test starts from a
  // clean store rather than inheriting what the previous one typed.
  app.launchArguments=["--reset-drafts","--body-preview","--episode-day-preview","--tab",tab]+extra
  app.launch()
  XCTAssertTrue(app.buttons["US"].waitForExistence(timeout:15));return app
 }
 func capture(_ name:String,_ app:XCUIApplication) {
  let shot=XCTAttachment(screenshot:app.screenshot());shot.name=name;shot.lifetime = .keepAlways;add(shot)
 }

 /// "It should always be present right above the bottom bar of navigation."
 func testTheBandAndTheNavigationAreBothPermanent() {
  let app=launch()
  for name in ["US","MIND","BODY","ALICIA","STUDIO"] {
   app.buttons[name].tap()
   XCTAssertTrue(app.buttons["dialogue.composer"].exists,"the band vanished on \(name)")
   XCTAssertTrue(app.buttons["composer.walk"].exists,"WALK vanished on \(name)")
   XCTAssertTrue(app.buttons["US"].exists,"the navigation vanished on \(name)")
  }
  capture("band-and-navigation-on-studio",app)
 }

 /// Opening the field must not take the navigation away with it — the old
 /// composer collapsed both the tab bar and itself on focus.
 func testTypingDoesNotRemoveTheNavigation() {
  let app=launch("mind")
  app.buttons["dialogue.composer"].tap()
  let field=app.textFields["conversation.field"]
  XCTAssertTrue(field.waitForExistence(timeout:10))
  field.tap();field.typeText("What is this actually asking of me?")
  capture("conversation-sheet-over-mind",app)
  XCTAssertTrue(app.buttons["conversation.send"].exists)
  app.buttons["conversation.close"].tap()
  XCTAssertTrue(app.buttons["MIND"].waitForExistence(timeout:10))
  XCTAssertTrue(app.buttons["dialogue.composer"].exists)
 }

 /// "a contextual layer that I'm talking to her on top of any of the sections"
 func testTheSectionTravelsIntoTheLayerAndTheDraftStaysWithIt() {
  let app=launch("body")
  app.buttons["dialogue.composer"].tap()
  XCTAssertTrue(app.staticTexts["conversation.context"].waitForExistence(timeout:10))
  XCTAssertTrue(app.staticTexts["conversation.context"].label.contains("Body"))
  let field=app.textFields["conversation.field"]
  field.tap();field.typeText("Why do I sleep worse after a late sauna?")
  capture("conversation-over-body",app)
  app.buttons["conversation.close"].tap()
  // The draft is a Body draft and stays one: it is visible on the band, and
  // it must not follow him to Mind.
  XCTAssertTrue(app.buttons["dialogue.composer"].label.contains("Continue your draft"))
  app.buttons["MIND"].tap()
  let onMind=app.buttons["dialogue.composer"].label
  let context=app.staticTexts["composer.context"].label
  XCTAssertFalse(onMind.contains("Continue your draft"),"band on Mind: \(onMind) | context: \(context)")
  app.buttons["BODY"].tap()
  XCTAssertTrue(app.buttons["dialogue.composer"].label.contains("Continue your draft"))
 }

 /// "the whole microphone should take the entire screen … I can see that
 /// word's big, so I can see as I'm talking if it's actually taking it well."
 /// WALK is the only spoken path now, and it opens that room.
 func testTalkOpensAFullScreenRoomWithTheWordsInFront() {
  let app=launch("us",["--episode-walk-preview"])
  app.buttons["composer.walk"].tap()
  XCTAssertTrue(app.staticTexts["listening.transcript"].waitForExistence(timeout:15))
  XCTAssertTrue(app.buttons["episode.finishWalk"].exists)
  // Type-agnostic: a combined accessibility element's XCUI type depends on
  // what SwiftUI folded into it, and the identifier is the stable contract.
  let state=app.descendants(matching:.any).matching(identifier:"walk.microphoneState").firstMatch
  XCTAssertTrue(state.exists)
  // Full screen: a cover leaves the tab bar in the accessibility tree, so the
  // claim to test is that nothing underneath can be reached while it is up.
  XCTAssertFalse(app.buttons["STUDIO"].isHittable)
  XCTAssertFalse(app.buttons["dialogue.composer"].isHittable)
  // The type itself is the claim: one line of the old 14-point strip was
  // about 17 points tall, one line of this is about 45.
  let words=app.staticTexts["listening.transcript"]
  XCTAssertGreaterThan(words.frame.height,40,"the words are not set large")
  // No width assertion: a static text reports its glyph bounds, not its
  // layout frame, so a short placeholder measures short however wide the
  // page is. The screenshot below is the record of the type on the page.
  XCTAssertGreaterThan(words.frame.height,app.frame.height*0.04,"the words are not given room")
  capture("listening-room",app)
  app.buttons["listening.close"].tap()
  XCTAssertTrue(app.buttons["US"].waitForExistence(timeout:10))
  XCTAssertFalse(app.buttons["composer.microphone"].exists,"the retired short-remark mic is back")
 }

 /// "the aura evidence is stale" — the sentence he reads must say how old it
 /// is and what would fix it, and must still show no measurement.
 func testARefusedBridgeExplainsItselfAndShowsNoNumbers() {
  let app=launch("body",["--body-stale-preview"])
  let line=app.staticTexts["body.staleness"]
  XCTAssertTrue(line.waitForExistence(timeout:10))
  XCTAssertTrue(line.label.contains("5 days old"),"no age in: \(line.label)")
  XCTAssertTrue(line.label.contains("rebuilt"),"no cause in: \(line.label)")
  XCTAssertFalse(app.staticTexts["OURA · AS OF unknown"].exists)
  capture("body-refusal-explained",app)
 }
}
""")

env=dict(os.environ,DEVELOPER_DIR='/Applications/Xcode.app/Contents/Developer')
result=pathlib.Path(os.environ.get('ALICIA_TEST_EVIDENCE_DIR',str(work)))/('home-conversation-ui-'+work.name+'.xcresult')
selected=[name for name in os.environ.get('ALICIA_UI_TESTS','').split(',') if name]
filters=['-only-testing:ContextUITests/HomeConversationUITests/'+name for name in selected]
subprocess.run(['xcodebuild','-project',str(project),'-scheme','Alicia','-destination','platform=iOS Simulator,name=iPhone 17','-derivedDataPath',str(work/'DerivedData'),'-resultBundlePath',str(result),'-parallel-testing-enabled','NO','CODE_SIGNING_ALLOWED=NO','test']+filters,env=env,check=True)
