"""Temporary XCUITest target for the real app; no changes to its project file."""
import json, os, pathlib, plistlib, shutil, subprocess, tempfile
import xml.etree.ElementTree as ET
root = pathlib.Path(__file__).resolve().parents[1]
work = pathlib.Path(tempfile.mkdtemp(prefix='alicia-private-review-ui-'))
print(work, flush=True)
project = work / 'Alicia.xcodeproj'
shutil.copytree(root / 'Alicia.xcodeproj', project)
for folder in ('Alicia','AliciaWidgets','Shared'):
    if folder == 'Alicia': shutil.copytree(root/folder, work/folder, ignore=shutil.ignore_patterns('Secrets.plist'))
    else: (work / folder).symlink_to(root / folder, target_is_directory=True)

# Temporary fixture only: production source is never edited. Generate silent
# audio in a fresh mock archive to exercise the real private review view.
ap=work/'Alicia/Core/AppStore.swift'
x=ap.read_text();x=x.replace('        reader.service = service', '        if isMock && ProcessInfo.processInfo.arguments.contains("--private-body-review-qa") {\n            voiceArchive.seedPrivateQA()\n            walkRecordingID = VoiceArchive.previewID\n            walkEpisodeID = ""; walkSurface = "body"\n            walkDraft = "Preview private reflection. These are editable fixture words."\n            showWalk = true\n        }\n        reader.service = service');ap.write_text(x)
vp=work/'Alicia/Core/VoiceEvidence.swift'
x=vp.read_text();x=x.replace('    func seedPreview() {', '    func seedPrivateQA() {\n        seedPreview()\n        guard var record = recording(Self.previewID) else { return }\n        record.context.surface_context = SurfaceContext(section: "body", captured_at: voiceTimestamp())\n        record.context.episode_id = ""\n        record.macProcessing = nil\n        try? replace(record)\n    }\n    func seedPreview() {');vp.write_text(x)

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
final class HomeConversationUITests: XCTestCase {
 func testPrivateReviewWithKeyboard() {
  continueAfterFailure = false
  let app = XCUIApplication()
  app.launchArguments = ["--body-preview", "--private-body-review-qa", "--tab", "body"]
  app.launch()
  let editor = app.textViews["listening.reviewEditor"]
  XCTAssertTrue(editor.waitForExistence(timeout: 20))
  editor.tap(); editor.typeText(" Corrected meaning.")
  XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
  let shot = XCTAttachment(screenshot: app.screenshot()); shot.name="private-review-keyboard";shot.lifetime = .keepAlways;add(shot)
  let send = app.buttons["episode.finishWalk"]
  XCTAssertTrue(send.exists)
  XCTAssertTrue(send.isHittable, "Send is hidden by the keyboard")
  XCTAssertTrue(app.buttons["REVIEW ORIGINAL AUDIO"].isHittable, "Original audio is hidden by the keyboard")
  let close=app.buttons["listening.close"]
  XCTAssertTrue(close.isHittable, "Close is clipped while editing")
  XCTAssertTrue((editor.value as? String ?? "").contains("Corrected meaning."))
  let reviewed = editor.value as? String
  app.buttons["REVIEW ORIGINAL AUDIO"].tap()
  let audioClose = app.navigationBars.buttons["CLOSE"]
  XCTAssertTrue(audioClose.waitForExistence(timeout: 10))
  audioClose.tap()
  XCTAssertTrue(editor.waitForExistence(timeout: 10))
  XCTAssertEqual(editor.value as? String, reviewed, "Audio review changed the edited draft")

 }
}
""")

env=dict(os.environ,DEVELOPER_DIR='/Applications/Xcode.app/Contents/Developer')
result=pathlib.Path(os.environ.get('ALICIA_TEST_EVIDENCE_DIR',str(work)))/('private-review-ui-'+work.name+'.xcresult')
selected=[name for name in os.environ.get('ALICIA_UI_TESTS','').split(',') if name]
filters=['-only-testing:ContextUITests/HomeConversationUITests/'+name for name in selected]
subprocess.run(['xcodebuild','-project',str(project),'-scheme','Alicia','-destination',os.environ.get('ALICIA_UI_DESTINATION', 'platform=iOS Simulator,name=iPhone 17'),'-derivedDataPath',str(work/'DerivedData'),'-resultBundlePath',str(result),'-parallel-testing-enabled','NO','CODE_SIGNING_ALLOWED=NO','-collect-test-diagnostics','never','test']+filters,env=env,check=True)
