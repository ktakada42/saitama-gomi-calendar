# ホーム画面ウィジェットのターゲットを ios/Runner.xcodeproj に追加する。
#
# 何度流しても同じ結果になるので、プロジェクトを作り直したときも再実行できる。
#   gem install xcodeproj && ruby scripts/add_widget_target.rb
#
# 手で追加するときに間違えやすい点を2つ、この中で吸収してある。
#   - 埋め込みフェーズを Thin Binary より前に置く（後ろだと依存が循環する）
#   - ウィジェットにもFlutterのxcconfigを参照させる
#     （FLUTTER_BUILD_NUMBER が解決されないとインストールに失敗する）
require 'xcodeproj'

project_path = 'ios/Runner.xcodeproj'
project = Xcodeproj::Project.open(project_path)

WIDGET_NAME = 'GomiWidget'
APP_BUNDLE_ID = 'io.github.ktakada42.saitamagomicalendar'
WIDGET_BUNDLE_ID = "#{APP_BUNDLE_ID}.#{WIDGET_NAME}"

# 既にあるなら作り直さない（何度流しても同じ結果になるように）
if project.targets.any? { |t| t.name == WIDGET_NAME }
  puts "既に存在: #{WIDGET_NAME}"
  exit 0
end

runner = project.targets.find { |t| t.name == 'Runner' }
abort 'Runnerターゲットが見つからない' unless runner

widget = project.new_target(
  :app_extension, WIDGET_NAME, :ios, '18.0', nil, :swift
)

# ソースをグループに登録する
group = project.main_group.find_subpath(WIDGET_NAME, true)
group.set_source_tree('SOURCE_ROOT')
group.set_path(WIDGET_NAME)

%w[GomiWidget.swift GomiData.swift].each do |name|
  ref = group.new_reference(name)
  widget.add_file_references([ref])
end
group.new_reference('Info.plist')
group.new_reference("#{WIDGET_NAME}.entitlements")

# Runner側にもentitlementsファイルをグループとして見せる
runner_group = project.main_group.find_subpath('Runner', true)
unless runner_group.files.any? { |f| f.path == 'Runner.entitlements' }
  runner_group.new_reference('Runner.entitlements')
end

widget.build_configurations.each do |config|
  s = config.build_settings
  s['PRODUCT_BUNDLE_IDENTIFIER'] = WIDGET_BUNDLE_ID
  s['PRODUCT_NAME'] = WIDGET_NAME
  s['INFOPLIST_FILE'] = "#{WIDGET_NAME}/Info.plist"
  s['CODE_SIGN_ENTITLEMENTS'] = "#{WIDGET_NAME}/#{WIDGET_NAME}.entitlements"
  s['IPHONEOS_DEPLOYMENT_TARGET'] = '18.0'
  s['TARGETED_DEVICE_FAMILY'] = '1'
  s['SWIFT_VERSION'] = '5.0'
  s['SKIP_INSTALL'] = 'YES'
  s['CURRENT_PROJECT_VERSION'] = '$(FLUTTER_BUILD_NUMBER)'
  s['MARKETING_VERSION'] = '$(FLUTTER_BUILD_NAME)'
  s['GENERATE_INFOPLIST_FILE'] = 'NO'
  # アプリ本体と同じチームで署名する
  s['DEVELOPMENT_TEAM'] = 'R9DDB6ZX39'
end

# アプリ本体にもApp Groupのentitlementsを設定する
runner.build_configurations.each do |config|
  config.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'Runner/Runner.entitlements'
end

# .appxの中にウィジェットを埋め込む
embed = runner.build_phases.find do |phase|
  phase.respond_to?(:name) && phase.name == 'Embed Foundation Extensions'
end
unless embed
  embed = project.new(Xcodeproj::Project::Object::PBXCopyFilesBuildPhase)
  embed.name = 'Embed Foundation Extensions'
  embed.symbol_dst_subfolder_spec = :plug_ins
  runner.build_phases << embed
end
build_file = embed.add_file_reference(widget.product_reference)
build_file.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }

runner.add_dependency(widget)

# Flutterの Thin Binary は最後に成果物を薄くするので、拡張の埋め込みは
# その前に済ませる。後ろに置くと Cycle inside Runner でビルドが落ちる。
thin_index = runner.build_phases.index do |ph|
  ph.respond_to?(:name) && ph.name == 'Thin Binary'
end
if thin_index && runner.build_phases.index(embed) > thin_index
  runner.build_phases.delete(embed)
  runner.build_phases.insert(thin_index, embed)
end

# 拡張のバージョンはアプリ本体と一致していないとインストールできない。
# FLUTTER_BUILD_NAME / NUMBER はFlutterのxcconfigで定義されるので、
# 本体と同じものを参照させて出どころを一本化する。
runner.build_configurations.each do |rc|
  wc = widget.build_configurations.find { |c| c.name == rc.name }
  next unless wc && rc.base_configuration_reference
  wc.base_configuration_reference = rc.base_configuration_reference
end

project.save
puts "追加した: #{WIDGET_NAME} (#{WIDGET_BUNDLE_ID})"
