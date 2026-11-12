import SwiftUI
import Charts
import AppKit
import EyeWatchCore

private enum EyePage: String, CaseIterable {
    // Keep navigation identifiers stable for the app's native smoke harness.
    case overview = "总览", trends = "数据趋势", settings = "提醒设置"
    func title(in language: AppLanguage) -> String {
        switch self {
        case .overview: return language.choose("今日", "Today")
        case .trends: return language.choose("用眼记录", "Screen time")
        case .settings: return language.choose("偏好设置", "Preferences")
        }
    }
    var symbol: String { switch self { case .overview: return "clock"; case .trends: return "chart.xyaxis.line"; case .settings: return "slider.horizontal.3" } }
}

@MainActor
struct ContentView: View {
    @Environment(\.mujianLanguage) private var language
    @ObservedObject var model: AppModel
    @State private var page: EyePage = .overview
    @State private var dayRange = 7
    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(MujianStyle.rule).frame(width: 1)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 32) {
                        header
                        switch page {
                        case .overview: TodayView(model: model)
                        case .trends: RecordView(model: model, dayRange: $dayRange)
                        case .settings: PreferencesView(model: model)
                        }
                        Color.clear.frame(height: 1).id("page-bottom")
                    }
                    .padding(32).frame(maxWidth: 1440).frame(maxWidth: .infinity).id("page-top")
                }
                .background(MujianStyle.paper)
                .onReceive(NotificationCenter.default.publisher(for: Notification.Name("EyeWatch.scroll"))) { note in
                    let destination = note.object as? String
                    if destination == "language" {
                        proxy.scrollTo("preferences.general", anchor: .top)
                    } else if destination == "detection" {
                        proxy.scrollTo("preferences.detection", anchor: .top)
                    } else {
                        let bottom = destination == "bottom"
                        proxy.scrollTo(bottom ? "page-bottom" : "page-top", anchor: bottom ? .bottom : .top)
                    }
                }
            }
        }
        .frame(minWidth: 1000, minHeight: 720)
        .foregroundStyle(MujianStyle.ink).tint(MujianStyle.accent)
        .preferredColorScheme(model.settings.theme == .system ? nil : (model.settings.theme == .dark ? .dark : .light))
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("EyeWatch.navigate"))) { note in
            if let title = note.object as? String, let destination = EyePage(rawValue: title) { page = destination }
        }
        .onChange(of: model.settings) { _ in model.saveSettings() }
        .alert(language.choose("请留意", "Please note"), isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button(language.choose("知道了", "OK"), role: .cancel) { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                MujianMark(size: 32)
                VStack(alignment: .leading, spacing: 4) {
                    Text(language.choose("歇会儿", "Breather"))
                        .font(language == .chinese ? .custom("Songti SC", size: 28) : .system(size: 25, design: .serif))
                        .lineLimit(1).minimumScaleFactor(0.85)
                    Text(language.choose("Breather", "歇会儿")).font(.system(size: 12)).foregroundStyle(MujianStyle.secondary)
                }
            }.padding(.top, 32).padding(.bottom, 48).padding(.horizontal, 24)
            VStack(spacing: 4) {
                ForEach(EyePage.allCases, id: \.self) { item in
                    Button { page = item } label: {
                        HStack(spacing: 12) {
                            Image(systemName: item.symbol).font(.system(size: 16, weight: .regular)).frame(width: 20)
                            Text(item.title(in: language)).font(.system(size: 14, weight: page == item ? .medium : .regular))
                            Spacer()
                        }.padding(.horizontal, 12).frame(height: 36)
                    }.buttonStyle(NavigationRowStyle(selected: page == item))
                }
            }.padding(.horizontal, 16)
            Spacer(minLength: 48)
            VStack(alignment: .leading, spacing: 12) {
                Hairline()
                Text(language.choose("用眼之间，留一段空白", "A pause between screen time")).font(.system(size: 12)).foregroundStyle(MujianStyle.secondary).fixedSize(horizontal: false, vertical: true)
                Text(model.settings.backupDirectory == nil ? language.choose("记录保存在此 Mac", "Records saved on this Mac") : language.choose("已启用文件夹备份", "Folder backup enabled"))
                    .font(.system(size: 11)).foregroundStyle(MujianStyle.muted)
            }.padding(24)
        }.frame(width: 224).background(MujianStyle.sidebar)
    }
    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text(page.title(in: language)).font(.system(size: 26, weight: .medium))
                Spacer()
                HStack(spacing: 8) {
                    Rectangle().fill(model.isPaused ? MujianStyle.muted : MujianStyle.accent).frame(width: 4, height: 4)
                    Text(model.phaseTitle).font(MujianStyle.caption).foregroundStyle(MujianStyle.secondary)
                }
            }
            HStack {
                Text(Date.now.formatted(.dateTime.year().month().day().weekday(.wide).locale(language.locale)))
                    .font(MujianStyle.caption).foregroundStyle(MujianStyle.secondary)
                Spacer()
                Text(page == .overview ? language.choose("用眼 / 休息", "Focus / rest") : (page == .trends ? language.choose("记录 / 回顾", "Records / review") : language.choose("规则 / 提醒", "Rules / reminders")))
                    .font(MujianStyle.caption).foregroundStyle(MujianStyle.muted)
            }
            Hairline()
        }
    }
}

private struct NavigationRowStyle: ButtonStyle {
    let selected: Bool
    @State private var hovered = false
    @Environment(\.isFocused) private var focused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(selected ? MujianStyle.ink : MujianStyle.secondary)
            .background(selected || hovered ? MujianStyle.raised : .clear, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(focused ? MujianStyle.accent : .clear, lineWidth: 2))
            .contentShape(Rectangle()).onHover { hovered = $0 }
            .animation(reduceMotion ? nil : MujianStyle.feedback, value: hovered)
    }
}

@MainActor
private struct TodayView: View {
    @Environment(\.mujianLanguage) private var language
    @ObservedObject var model: AppModel
    private var progress: Double { min(1, max(0, model.engine.workElapsed / max(1, model.settings.workSeconds * model.settings.fatigueThreshold / 100))) }
    private var locked: Bool { model.engine.phase == .resting && model.engine.breakIsStrict }
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .top, spacing: 32) {
                VStack(alignment: .leading, spacing: 24) {
                    HStack {
                        Text(language.choose("当前用眼负荷", "Current eye strain")).font(.system(size: 14, weight: .medium))
                        Spacer()
                        Image(systemName: "info.circle").font(.system(size: 14)).foregroundStyle(MujianStyle.muted)
                            .help(language.choose("按活跃用眼与休息时间估算，仅用于安排休息，不是医学测量", "Estimated from active screen time and rest. For scheduling breaks; not a medical measurement."))
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(Int(model.fatigue))").font(.system(size: 72, weight: .regular)).monospacedDigit().foregroundStyle(MujianStyle.accent)
                        Text("/ 100").font(.system(size: 18)).foregroundStyle(MujianStyle.muted)
                        Spacer()
                    }
                    FatigueScale(value: model.fatigue, threshold: model.settings.fatigueThreshold)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(stateDescription).font(.system(size: 13)).foregroundStyle(MujianStyle.secondary)
                        Text(language.choose("检测依据：\(model.detectionStatus)", "Activity source: \(model.detectionStatus)"))
                            .font(MujianStyle.caption).foregroundStyle(MujianStyle.muted)
                    }.fixedSize(horizontal: false, vertical: true)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Rectangle().fill(MujianStyle.rule).frame(width: 1, height: 244)
                VStack(alignment: .leading, spacing: 32) {
                    Measure(title: language.choose("今日累计用眼", "Screen time today"), value: language.duration(model.today.activeSeconds), note: language.choose("仅记录活跃使用时间", "Active use only"))
                    Measure(title: language.choose("休息完成率", "Break completion"), value: model.today.breaksOffered > 0 ? "\(Int(model.today.completionRate * 100))%" : "—", note: language.choose("完成 \(model.today.breaksCompleted) / 提醒 \(model.today.breaksOffered) 次", "\(model.today.breaksCompleted) completed / \(model.today.breaksOffered) offered"))
                }.frame(width: 224, alignment: .leading)
            }
            Hairline()
            nextBreak
            Hairline()
            HourlyUsage(record: model.today)
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text("20 / 20 / 20").font(MujianStyle.mono).foregroundStyle(MujianStyle.ink)
                Text(language.choose("用眼 20 分钟后，望向 6 米外至少 20 秒", "Every 20 minutes, look 20 feet away for at least 20 seconds")).font(MujianStyle.caption).foregroundStyle(MujianStyle.secondary)
                Spacer(minLength: 0)
            }
        }
    }
    private var stateDescription: String {
        switch model.engine.phase {
        case .monitoring: return language.choose("活跃用眼时上升，离开电脑后逐渐恢复", "Rises during active use and recovers when you step away")
        case .idle: return language.choose("检测到无操作，正在降低用眼负荷", "No activity detected. Eye strain is recovering")
        case .resting: return language.choose("休息计时进行中，结束后恢复监测", "Your break is in progress. Monitoring resumes when it ends")
        case .paused: return language.choose("监测已暂停，当前时间不计入记录", "Monitoring is paused. This time is not recorded")
        case .snoozed: return language.choose("提醒已延后，用眼时间仍会继续记录", "Reminder snoozed. Screen time is still being recorded")
        case .outsideSchedule: return language.choose("当前时段不发出提醒，用眼记录仍在继续", "Outside reminder hours. Screen time is still being recorded")
        }
    }
    private var nextBreak: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .center, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.engine.phase == .resting ? language.choose("本次休息剩余", "Break remaining") : (model.engine.phase == .snoozed ? language.choose("延后提醒剩余", "Snooze remaining") : language.choose("距离下次休息", "Next break in")))
                        .font(.system(size: 12)).foregroundStyle(MujianStyle.secondary)
                    Text(model.remainingText).font(.system(size: 40, weight: .regular)).monospacedDigit()
                }
                Spacer(minLength: 12)
                HStack(spacing: 8) {
                    Button(model.isPaused ? language.choose("继续监测", "Resume") : language.choose("暂停监测", "Pause"), action: model.pauseResume).buttonStyle(QuietButtonStyle()).disabled(locked)
                    Menu {
                        Button(language.choose("延后提醒 5 分钟", "Snooze for 5 minutes"), action: model.snooze).disabled(locked)
                        if model.engine.phase == .resting { Button(language.choose("跳过这次休息", "Skip this break"), action: model.skipBreak).disabled(locked) }
                    } label: { Image(systemName: "ellipsis").font(.system(size: 16)).frame(width: 20, height: 24) }
                    .menuStyle(.borderlessButton).tint(MujianStyle.secondary).fixedSize().help(language.choose("更多休息选项", "More break options")).accessibilityLabel(language.choose("更多休息选项", "More break options"))
                    Button(language.choose("开始休息", "Start break"), action: model.takeBreak).buttonStyle(QuietButtonStyle(primary: true)).disabled(model.engine.phase == .resting)
                }
            }
            VStack(spacing: 8) {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(MujianStyle.rule)
                        Rectangle().fill(MujianStyle.ink.opacity(0.7)).frame(width: proxy.size.width * progress)
                    }
                }.frame(height: 2).accessibilityLabel(language.choose("当前用眼进度 \(Int(progress * 100))%", "Current screen time progress \(Int(progress * 100))%"))
                HStack {
                    Text(language.choose("本轮 \(language.duration(model.engine.workElapsed))", "This session: \(language.duration(model.engine.workElapsed))"))
                    Spacer()
                    Text(language.choose("用眼 \(Int(model.settings.workSeconds / 60)) 分钟 / 休息 \(Int(model.settings.restSeconds)) 秒", "Work \(Int(model.settings.workSeconds / 60)) min / rest \(Int(model.settings.restSeconds)) sec"))
                }.font(.system(size: 11, design: .monospaced)).foregroundStyle(MujianStyle.muted)
            }
        }
    }
}

private struct FatigueScale: View {
    @Environment(\.mujianLanguage) private var language
    let value: Double
    let threshold: Double
    var body: some View {
        VStack(spacing: 12) {
            GeometryReader { proxy in
                let width = proxy.size.width
                ZStack(alignment: .bottomLeading) {
                    Path { p in
                        for n in 0...40 {
                            let x = CGFloat(n) / 40 * width
                            p.move(to: CGPoint(x: x, y: n % 10 == 0 ? 0 : 8)); p.addLine(to: CGPoint(x: x, y: 24))
                        }
                    }.stroke(MujianStyle.chart.opacity(0.65), lineWidth: 1)
                    Rectangle().fill(MujianStyle.accent).frame(width: 2, height: 32).offset(x: max(0, min(width - 2, width * value / 100)))
                }
            }.frame(height: 32)
            HStack {
                ForEach([0, 25, 50, 75, 100], id: \.self) { number in
                    Text("\(number)").font(.system(size: 11, design: .monospaced)).foregroundStyle(MujianStyle.muted)
                    if number != 100 { Spacer() }
                }
            }
            HStack {
                Text(language.choose("估算值", "Estimate")).foregroundStyle(MujianStyle.muted)
                Spacer()
                Text(language.choose("\(Int(threshold)) 时提醒", "Remind at \(Int(threshold))")).foregroundStyle(MujianStyle.secondary)
            }.font(.system(size: 11))
        }.accessibilityElement(children: .ignore).accessibilityLabel(language.choose("用眼负荷 \(Int(value))，提醒阈值 \(Int(threshold))", "Eye strain \(Int(value)), reminder threshold \(Int(threshold))"))
    }
}

private struct Measure: View {
    let title: String
    let value: String
    var note: String = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.system(size: 12)).foregroundStyle(MujianStyle.secondary)
            Text(value).font(.system(size: 28, weight: .regular)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.75)
            if !note.isEmpty { Text(note).font(.system(size: 11)).foregroundStyle(MujianStyle.muted).fixedSize(horizontal: false, vertical: true) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct HourlyUsage: View {
    @Environment(\.mujianLanguage) private var language
    let record: DailyRecord
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SectionHeading(title: language.choose("今日用眼分布", "Screen time by hour"), detail: language.choose("每小时 / 分钟", "Minutes per hour"))
            Chart(Array(record.hourlySeconds.prefix(24).enumerated()), id: \.offset) { item in
                RectangleMark(xStart: .value(language.choose("开始小时", "Start hour"), Double(item.offset) - 0.32), xEnd: .value(language.choose("结束小时", "End hour"), Double(item.offset) + 0.32), yStart: .value(language.choose("起点", "Baseline"), 0.0), yEnd: .value(language.choose("分钟", "Minutes"), item.element / 60))
                    .foregroundStyle(item.offset == Calendar.current.component(.hour, from: .now) ? MujianStyle.accent : MujianStyle.chart)
            }
            .chartXScale(domain: -0.5...23.5).chartYScale(domain: 0.0...60.0)
            .chartXAxis {
                AxisMarks(values: [0, 4, 8, 12, 16, 20, 23]) { tick in
                    AxisValueLabel { if let hour = tick.as(Int.self) { Text(String(format: "%02d", hour)).font(.system(size: 11, design: .monospaced)).foregroundStyle(MujianStyle.muted) } }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: [0, 30, 60]) { tick in
                    AxisGridLine().foregroundStyle(MujianStyle.rule)
                    AxisValueLabel { if let number = tick.as(Int.self) { Text("\(number)").font(.system(size: 11, design: .monospaced)).foregroundStyle(MujianStyle.muted) } }
                }
            }
            .frame(height: 160)
            .overlay {
                if record.activeSeconds < 1 {
                    Text(language.choose("开始使用电脑后，记录会显示在这里", "Your activity will appear here as you use your Mac")).font(MujianStyle.caption).foregroundStyle(MujianStyle.secondary)
                        .padding(12).background(MujianStyle.paper)
                }
            }
        }
    }
}

@MainActor
private struct RecordView: View {
    @Environment(\.mujianLanguage) private var language
    @ObservedObject var model: AppModel
    @Binding var dayRange: Int
    private var selected: [DailyRecord] {
        if dayRange == 0 { return model.records.sorted { $0.day < $1.day } }
        let start = Calendar.current.date(byAdding: .day, value: -(dayRange - 1), to: Calendar.current.startOfDay(for: .now)) ?? .now
        return model.records.filter { $0.day >= dayKey(start) && $0.day <= dayKey(.now) }.sorted { $0.day < $1.day }
    }
    private var offered: Int { selected.reduce(0) { $0 + $1.breaksOffered } }
    private var completed: Int { selected.reduce(0) { $0 + $1.breaksCompleted } }
    private var hasActivity: Bool { selected.contains { $0.activeSeconds > 0 || $0.breaksOffered > 0 } }
    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            HStack {
                Picker(language.choose("时间范围", "Date range"), selection: $dayRange) {
                    Text(language.choose("7 天", "7 days")).tag(7)
                    Text(language.choose("30 天", "30 days")).tag(30)
                    Text(language.choose("90 天", "90 days")).tag(90)
                    Text(language.choose("12 个月", "12 months")).tag(365)
                    Text(language.choose("全部", "All")).tag(0)
                }.pickerStyle(.segmented).frame(width: 360)
                Spacer()
                Button(language.choose("导出 CSV", "Export CSV"), action: model.exportCSV).buttonStyle(QuietButtonStyle())
            }
            HStack(alignment: .top, spacing: 32) {
                Measure(title: language.choose("累计用眼", "Total screen time"), value: language.duration(selected.reduce(0) { $0 + $1.activeSeconds }), note: dayRange == 0 ? language.choose("全部记录", "All records") : language.choose("最近 \(dayRange) 天", "Last \(dayRange) days"))
                Measure(title: language.choose("完成休息", "Breaks completed"), value: language.choose("\(completed) 次", "\(completed)"), note: language.choose("共提醒 \(offered) 次", "\(offered) breaks offered"))
                Measure(title: language.choose("休息完成率", "Break completion"), value: offered > 0 ? "\(Int(Double(completed) / Double(offered) * 100))%" : "—", note: language.choose("系统通知不计入", "System notifications excluded"))
            }
            Hairline()
            VStack(alignment: .leading, spacing: 24) {
                SectionHeading(title: language.choose("每日用眼时长", "Daily screen time"), detail: language.choose("小时", "Hours"))
                if hasActivity {
                    Chart(selected) { record in
                        BarMark(x: .value(language.choose("日期", "Date"), record.day), y: .value(language.choose("小时", "Hours"), record.activeSeconds / 3600))
                            .foregroundStyle(record.day == dayKey(.now) ? MujianStyle.accent : MujianStyle.chart)
                    }
                    .chartXAxis { recordAxis }
                    .chartYAxis { AxisMarks(position: .leading) { AxisGridLine().foregroundStyle(MujianStyle.rule); AxisValueLabel().font(MujianStyle.mono).foregroundStyle(MujianStyle.muted) } }
                    .frame(height: 248)
                } else { NoRecords(title: language.choose("还没有用眼记录", "No screen time recorded yet"), detail: language.choose("监测开始后，每日使用时间会自动记在这里", "Daily activity is recorded automatically when monitoring starts")).frame(height: 248) }
            }
            Hairline()
            VStack(alignment: .leading, spacing: 20) {
                SectionHeading(title: language.choose("休息完成率", "Break completion"), detail: language.choose("完成倒计时 / 弹窗次数", "Completed / offered breaks"))
                if offered > 0 {
                    Chart(selected) { record in
                        LineMark(x: .value(language.choose("日期", "Date"), record.day), y: .value(language.choose("完成率", "Completion rate"), record.completionRate * 100)).foregroundStyle(MujianStyle.ink)
                        PointMark(x: .value(language.choose("日期", "Date"), record.day), y: .value(language.choose("完成率", "Completion rate"), record.completionRate * 100)).foregroundStyle(MujianStyle.ink).symbolSize(20)
                    }.chartYScale(domain: 0...100)
                        .chartXAxis { recordAxis }
                        .chartYAxis { AxisMarks(position: .leading, values: [0, 50, 100]) { AxisGridLine().foregroundStyle(MujianStyle.rule); AxisValueLabel().font(MujianStyle.mono).foregroundStyle(MujianStyle.muted) } }
                        .frame(height: 128)
                } else {
                    HStack {
                        Text(language.choose("尚未收到休息提醒", "No breaks offered yet")).font(MujianStyle.body).foregroundStyle(MujianStyle.secondary)
                        Spacer()
                        Button(language.choose("开始休息", "Start break"), action: model.takeBreak).buttonStyle(QuietButtonStyle())
                    }.frame(height: 96)
                }
            }
            Hairline()
            VStack(alignment: .leading, spacing: 20) {
                SectionHeading(title: language.choose("疲劳峰值时长", "Time at peak strain"), detail: language.choose("达到 100 后继续用眼 / 分钟", "Minutes of use after reaching 100"))
                if hasActivity {
                    Chart(selected) { record in
                        BarMark(x: .value(language.choose("日期", "Date"), record.day), y: .value(language.choose("分钟", "Minutes"), record.peakFatigueSeconds / 60)).foregroundStyle(MujianStyle.accent.opacity(0.65))
                    }.chartXAxis { recordAxis }
                        .chartYAxis { AxisMarks(position: .leading) { AxisGridLine().foregroundStyle(MujianStyle.rule); AxisValueLabel().font(MujianStyle.mono).foregroundStyle(MujianStyle.muted) } }
                        .frame(height: 128)
                } else { Text(language.choose("没有达到疲劳峰值的记录", "No time at peak strain recorded")).font(MujianStyle.caption).foregroundStyle(MujianStyle.secondary).frame(height: 96) }
            }
        }
    }
    private var recordAxis: some AxisContent {
        AxisMarks(values: .automatic(desiredCount: dayRange == 7 ? 7 : 5)) { tick in
            AxisValueLabel {
                if let key = tick.as(String.self) { Text(shortDay(key, language: language)).font(.system(size: 11, design: .monospaced)).foregroundStyle(MujianStyle.muted) }
            }
        }
    }
}

@MainActor
private struct PreferencesView: View {
    @Environment(\.mujianLanguage) private var language
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            timing
            detection
            schedule
            reminders
            general
            shortcuts
            backup
            Text(language.choose("更改会自动保存", "Changes are saved automatically")).font(MujianStyle.caption).foregroundStyle(MujianStyle.muted)
        }
    }
    private var timing: some View {
        PreferenceSection(title: language.choose("工作与休息", "Work and rest"), detail: language.choose("安排用眼间隔", "Set your break rhythm")) {
            PreferenceRow(language.choose("检测模式", "Monitoring mode"), detail: language.choose("智能模式在无操作时恢复；阅读模式在屏幕开启时持续计时", "Smart mode recovers during inactivity; reading mode keeps counting while the screen is on")) {
                Picker(language.choose("检测模式", "Monitoring mode"), selection: $model.settings.monitoringMode) {
                    ForEach(MonitoringMode.allCases) { mode in Text(monitoringTitle(mode)).tag(mode) }
                }.labelsHidden().frame(width: 188)
            }
            Hairline()
            PreferenceRow(language.choose("连续用眼", "Work interval"), detail: language.choose("达到设定时长后提醒休息", "Remind you to rest after this much screen time")) {
                Stepper(value: $model.settings.workSeconds, in: 60...7200, step: 60) {
                    Text(language.choose("\(Int(model.settings.workSeconds / 60)) 分钟", "\(Int(model.settings.workSeconds / 60)) min")).monospacedDigit()
                }.frame(width: 128).accessibilityLabel(language.choose("连续用眼", "Work interval"))
            }
            Hairline()
            PreferenceRow(language.choose("每次休息", "Break duration"), detail: language.choose("建议至少远眺 20 秒", "Look into the distance for at least 20 seconds")) {
                Stepper(value: $model.settings.restSeconds, in: 5...1800, step: 5) {
                    Text(language.choose("\(Int(model.settings.restSeconds)) 秒", "\(Int(model.settings.restSeconds)) sec")).monospacedDigit()
                }.frame(width: 128).accessibilityLabel(language.choose("每次休息", "Break duration"))
            }
            Hairline()
            PreferenceRow(language.choose("提醒阈值", "Reminder threshold"), detail: language.choose("较低的数值会提前提醒", "Lower values trigger an earlier reminder")) {
                HStack(spacing: 12) {
                    Slider(value: $model.settings.fatigueThreshold, in: 20...100, step: 5).frame(width: 128).accessibilityLabel(language.choose("提醒阈值", "Reminder threshold"))
                    Text("\(Int(model.settings.fatigueThreshold))").monospacedDigit().frame(width: 32, alignment: .trailing)
                }
            }
            Hairline()
            PreferenceRow(language.choose("离开判断", "Idle detection"), detail: language.choose("无操作达到此时间后，停止累计用眼时长", "Stop counting screen time after this period of inactivity")) {
                Stepper(value: $model.settings.idleSeconds, in: 15...600, step: 15) {
                    Text(language.choose("\(Int(model.settings.idleSeconds)) 秒", "\(Int(model.settings.idleSeconds)) sec")).monospacedDigit()
                }.frame(width: 128).accessibilityLabel(language.choose("离开判断", "Idle detection"))
            }
        }
    }
    private var detection: some View {
        PreferenceSection(title: language.choose("活动检测与权限", "Activity detection and permissions"), detail: language.choose("可选增强", "Optional enhancements")) {
            Text(language.choose("仅推断电脑是否在使用，不使用摄像头或识别人脸，也不能判断真人是否在场。两项增强默认关闭；未开启、未授权或不可用时，仍使用系统空闲时间。锁屏或休眠时暂停检测；屏幕可用时，阅读 / 观影模式仍可持续计时。", "These signals estimate computer use. They do not use a camera, recognize faces, or establish that a person is present. Both enhancements are off by default. Disabled, unauthorized, or unavailable enhancements fall back to system idle time. Detection pauses while locked or asleep. Reading / video mode can keep counting while the screen is available."))
                .font(MujianStyle.caption).foregroundStyle(MujianStyle.secondary).fixedSize(horizontal: false, vertical: true)
            Hairline()
            PreferenceRow(language.choose("增强键鼠检测", "Enhanced input detection"), detail: language.choose("需要辅助功能权限；仅记录键鼠活动发生时间，不读取或保存按键内容", "Requires Accessibility permission. Records only when keyboard or mouse activity occurs; does not read or save keystroke content")) {
                Toggle(language.choose("增强键鼠检测", "Enhanced input detection"), isOn: $model.settings.enhancedInputDetection).labelsHidden().toggleStyle(.switch)
            }
            VStack(alignment: .leading, spacing: 12) {
                Text(language.choose("辅助功能权限：", "Accessibility permission: ") + permissionStatus(model.inputPermissionGranted))
                    .font(MujianStyle.caption).foregroundStyle(MujianStyle.secondary)
                Text(language.choose("检测状态：", "Detection status: ") + detectionState(enabled: model.settings.enhancedInputDetection, authorized: model.inputPermissionGranted, running: model.inputDetectionRunning))
                    .font(MujianStyle.caption).foregroundStyle(MujianStyle.secondary)
                HStack(spacing: 8) {
                    Button(language.choose("授权键鼠检测", "Authorize input detection"), action: model.requestInputPermission)
                        .buttonStyle(QuietButtonStyle()).disabled(model.inputPermissionGranted)
                    Button(language.choose("打开系统设置", "Open System Settings"), action: model.openInputPermissionSettings)
                        .buttonStyle(QuietButtonStyle())
                        .accessibilityLabel(language.choose("打开辅助功能权限设置", "Open Accessibility permission settings"))
                }
            }.fixedSize(horizontal: false, vertical: true)
            Hairline()
            PreferenceRow(language.choose("屏幕变化检测", "Screen change detection"), detail: language.choose("需要屏幕录制权限；低频采样低分辨率画面，仅比较内存中的差异，不保存或上传画面", "Requires Screen Recording permission. Compares low-resolution frames at a low rate in memory; frames are never saved or uploaded")) {
                Toggle(language.choose("屏幕变化检测", "Screen change detection"), isOn: $model.settings.screenActivityDetection).labelsHidden().toggleStyle(.switch)
            }
            VStack(alignment: .leading, spacing: 12) {
                Text(language.choose("屏幕录制权限：", "Screen Recording permission: ") + permissionStatus(model.screenPermissionGranted))
                    .font(MujianStyle.caption).foregroundStyle(MujianStyle.secondary)
                Text(language.choose("检测状态：", "Detection status: ") + detectionState(enabled: model.settings.screenActivityDetection, authorized: model.screenPermissionGranted, running: model.screenDetectionRunning))
                    .font(MujianStyle.caption).foregroundStyle(MujianStyle.secondary)
                Text(language.choose("视频持续变化可减少无键鼠操作时被误判为离开，但不能证明人在场。", "Ongoing video changes can help avoid an idle reading when there is no input, but cannot prove that someone is present."))
                    .font(MujianStyle.caption).foregroundStyle(MujianStyle.secondary)
                HStack(spacing: 8) {
                    Button(language.choose("授权屏幕检测", "Authorize screen detection"), action: model.requestScreenPermission)
                        .buttonStyle(QuietButtonStyle()).disabled(model.screenPermissionGranted)
                    Button(language.choose("打开系统设置", "Open System Settings"), action: model.openScreenPermissionSettings)
                        .buttonStyle(QuietButtonStyle())
                        .accessibilityLabel(language.choose("打开屏幕录制权限设置", "Open Screen Recording permission settings"))
                }
            }.fixedSize(horizontal: false, vertical: true)
            Hairline()
            VStack(alignment: .leading, spacing: 12) {
                Text(language.choose("当前检测依据：\(model.detectionStatus)", "Current activity source: \(model.detectionStatus)"))
                    .font(MujianStyle.caption).foregroundStyle(MujianStyle.secondary)
                if let error = model.activityMonitorError {
                    Text(language.choose("增强检测提示：\(error)", "Detection notice: \(error)"))
                        .font(MujianStyle.caption).foregroundStyle(MujianStyle.accent)
                }
                Text(language.choose("更改权限后可刷新状态；若系统提示重启应用，请按提示操作。开启开关不会自动申请权限，请使用上方授权按钮。", "Refresh after changing permissions. Restart the app if macOS asks you to. Enabling a switch does not request permission; use the authorization buttons above."))
                    .font(MujianStyle.caption).foregroundStyle(MujianStyle.secondary)
                Button(language.choose("刷新权限状态", "Refresh permissions"), action: model.refreshDetectionPermissions).buttonStyle(QuietButtonStyle())
            }.fixedSize(horizontal: false, vertical: true)
        }.id("preferences.detection")
    }
    private func permissionStatus(_ granted: Bool) -> String {
        granted ? language.choose("已授权", "Granted") : language.choose("未授权", "Not granted")
    }
    private func detectionState(enabled: Bool, authorized: Bool, running: Bool) -> String {
        guard enabled else { return language.choose("已关闭", "Off") }
        guard authorized else { return language.choose("已启用，等待授权", "Enabled, awaiting permission") }
        guard !model.isDetectionSuspended else { return language.choose("已启用，暂时暂停", "Enabled, temporarily suspended") }
        return running ? language.choose("正在运行", "Running") : language.choose("已授权，当前不可用；使用系统空闲时间", "Granted, currently unavailable; using system idle time")
    }
    private var schedule: some View {
        PreferenceSection(title: language.choose("提醒时段", "Reminder schedule"), detail: language.choose("时段外仍记录用眼", "Screen time is always recorded")) {
            PreferenceRow(language.choose("仅在指定时段提醒", "Use a reminder schedule"), detail: language.choose("关闭后全天提醒", "Turn off to allow reminders at any time")) {
                Toggle(language.choose("指定时段", "Reminder schedule"), isOn: $model.settings.scheduleEnabled).labelsHidden().toggleStyle(.switch)
            }
            if model.settings.scheduleEnabled {
                Hairline()
                PreferenceRow(language.choose("每日时段", "Daily hours"), detail: language.choose("结束早于开始时跨越午夜", "An earlier end time continues past midnight")) {
                    HStack(spacing: 8) {
                        hourPicker(language.choose("开始", "Start"), $model.settings.scheduleStartHour)
                        Text(language.choose("至", "to")).foregroundStyle(MujianStyle.muted)
                        hourPicker(language.choose("结束", "End"), $model.settings.scheduleEndHour)
                    }
                }
                Hairline()
                PreferenceRow(language.choose("重复日期", "Repeat on"), detail: language.choose("选择需要提醒的星期", "Choose which days reminders are active")) {
                    HStack(spacing: 4) {
                        ForEach([2,3,4,5,6,7,1], id: \.self) { day in
                            Button {
                                if model.settings.weekdays.contains(day) { model.settings.weekdays.remove(day) } else { model.settings.weekdays.insert(day) }
                            } label: { Text(weekday(day, language: language)).font(.system(size: 12)).frame(width: language == .chinese ? 28 : 32, height: 32) }
                                .buttonStyle(DayStyle(selected: model.settings.weekdays.contains(day)))
                                .accessibilityLabel(fullWeekday(day, language: language)).accessibilityAddTraits(model.settings.weekdays.contains(day) ? .isSelected : [])
                        }
                    }
                }
            }
        }
    }
    private var reminders: some View {
        PreferenceSection(title: language.choose("休息体验", "Break experience"), detail: language.choose("提醒与休息画面", "Reminders and break screens")) {
            PreferenceRow(language.choose("提醒方式", "Reminder style"), detail: reminderDetail) {
                Picker(language.choose("提醒方式", "Reminder style"), selection: $model.settings.reminderStyle) {
                    ForEach(ReminderStyle.allCases) { style in Text(reminderTitle(style)).tag(style) }
                }.labelsHidden().frame(width: 188)
            }
            Hairline()
            PreferenceRow(language.choose("严格休息", "Strict breaks"), detail: language.choose("当前休息完成前不能跳过", "A break cannot be skipped before it finishes")) {
                Toggle(language.choose("严格休息", "Strict breaks"), isOn: $model.settings.strictMode).labelsHidden().toggleStyle(.switch).disabled(model.engine.phase == .resting)
            }
            if !model.settings.strictMode {
                Hairline()
                PreferenceRow(language.choose("解题后跳过", "Solve before skipping"), detail: language.choose("跳过或延后当前休息前先完成加法题", "Solve an addition problem before skipping or snoozing a break")) {
                    Toggle(language.choose("解题后跳过", "Solve before skipping"), isOn: $model.settings.skipChallengeEnabled).labelsHidden().toggleStyle(.switch).disabled(model.engine.phase == .resting)
                }
            }
            Hairline()
            PreferenceRow(language.choose("提前一分钟通知", "One-minute warning"), detail: language.choose("需要允许系统通知", "Requires notification permission")) {
                Toggle(language.choose("提前通知", "Advance notice"), isOn: $model.settings.advanceNoticeEnabled).labelsHidden().toggleStyle(.switch)
            }
            Hairline()
            PreferenceRow(language.choose("提示音", "Sound"), detail: language.choose("休息开始和结束时播放", "Play a sound when a break starts and ends")) {
                Toggle(language.choose("提示音", "Sound"), isOn: $model.settings.soundEnabled).labelsHidden().toggleStyle(.switch)
            }
            Hairline()
            VStack(alignment: .leading, spacing: 12) {
                Text(language.choose("休息文字", "Break message")).font(MujianStyle.body)
                TextField(language.choose("远眺片刻，稍后继续", "Look into the distance. Continue in a moment."), text: Binding(get: { language.restMessage(model.settings.restMessage) }, set: { model.settings.restMessage = $0 }), axis: .vertical)
                    .textFieldStyle(.roundedBorder).lineLimit(2...4).font(MujianStyle.body)
                    .accessibilityLabel(language.choose("休息文字", "Break message"))
            }.padding(.vertical, 8)
            Hairline()
            PreferenceRow(language.choose("休息背景", "Break background"), detail: model.settings.wallpaperPath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? language.choose("默认深色背景", "Default dark background")) {
                HStack(spacing: 8) {
                    if model.settings.wallpaperPath != nil { Button(language.choose("恢复默认", "Reset"), action: model.clearWallpaper).buttonStyle(QuietButtonStyle()) }
                    Button(language.choose("选择图片", "Choose image"), action: model.chooseWallpaper).buttonStyle(QuietButtonStyle())
                }
            }
        }
    }
    private var general: some View {
        PreferenceSection(title: language.choose("通用", "General"), detail: language.choose("外观与系统", "Appearance and system")) {
            PreferenceRow(language.choose("语言", "Language")) {
                Picker(language.choose("语言", "Language"), selection: $model.settings.language) {
                    ForEach(AppLanguage.allCases) { option in Text(option.displayName).tag(option) }
                }.labelsHidden().frame(width: 188)
            }
            Hairline()
            PreferenceRow(language.choose("外观", "Appearance")) {
                Picker(language.choose("外观", "Appearance"), selection: $model.settings.theme) {
                    ForEach(AppTheme.allCases) { theme in Text(themeTitle(theme)).tag(theme) }
                }.labelsHidden().frame(width: 188)
            }
            Hairline()
            PreferenceRow(language.choose("每日用眼上限", "Daily screen limit"), detail: language.choose("达到总时长后通知，继续记录用眼", "Notify at the limit and keep recording screen time")) {
                Toggle(language.choose("用眼上限", "Daily screen limit"), isOn: $model.settings.dailyLimitEnabled).labelsHidden().toggleStyle(.switch)
            }
            if model.settings.dailyLimitEnabled {
                Hairline()
                PreferenceRow(language.choose("上限时长", "Daily limit")) {
                    Stepper(value: $model.settings.dailyLimitHours, in: 0.5...16, step: 0.5) {
                        Text(String(format: language.choose("%.1f 小时", "%.1f hr"), locale: language.locale, model.settings.dailyLimitHours)).monospacedDigit()
                    }.frame(width: 128).accessibilityLabel(language.choose("上限时长", "Daily limit"))
                }
            }
            Hairline()
            PreferenceRow(language.choose("登录时启动", "Launch at login")) {
                Toggle(language.choose("登录启动", "Launch at login"), isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) })).labelsHidden().toggleStyle(.switch)
            }
            Hairline()
            PreferenceRow(language.choose("在程序坞中显示", "Show in Dock"), detail: language.choose("关闭后仅在菜单栏常驻，仍可从菜单栏打开主窗口", "Turn off to stay in the menu bar. You can still open the main window from there")) {
                Toggle(language.choose("在程序坞中显示", "Show in Dock"), isOn: $model.settings.showDockIcon).labelsHidden().toggleStyle(.switch)
            }
            Hairline()
            PreferenceRow(language.choose("菜单栏倒计时", "Menu bar countdown"), detail: language.choose("在菜单栏查看下一次休息时间", "Show time until the next break in the menu bar")) {
                Toggle(language.choose("菜单栏倒计时", "Menu bar countdown"), isOn: $model.settings.showMenuBarTime).labelsHidden().toggleStyle(.switch)
            }
        }.id("preferences.general")
    }
    private var shortcuts: some View {
        PreferenceSection(title: language.choose("键盘快捷键", "Keyboard shortcuts"), detail: language.choose("应用内使用", "While the app is active")) {
            shortcutRow(language.choose("关闭当前窗口，继续后台监测", "Close the window; keep monitoring"), "⌘W")
            Hairline()
            shortcutRow(language.choose("最小化普通窗口", "Minimize a normal window"), "⌘M")
            Hairline()
            shortcutRow(language.choose("偏好设置", "Preferences"), "⌘,")
            Hairline()
            shortcutRow(language.choose("显示主窗口", "Show main window"), "⌘0")
            Hairline()
            shortcutRow(language.choose("开始休息", "Start a break"), "⌘⇧R")
            Hairline()
            shortcutRow(language.choose("退出应用", "Quit the app"), "⌘Q")
            Text(language.choose("休息窗口的关闭遵循跳过和解题规则；严格休息不能关闭或最小化，退出应用仍可用", "Closing a break follows skip and challenge rules. Strict breaks cannot be closed or minimized; quitting remains available"))
                .font(MujianStyle.caption).foregroundStyle(MujianStyle.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
    private func shortcutRow(_ title: String, _ key: String) -> some View {
        HStack {
            Text(title).font(MujianStyle.body)
            Spacer()
            Text(key).font(.system(size: 13, design: .monospaced)).foregroundStyle(MujianStyle.secondary)
        }.frame(minHeight: 32)
    }
    private var backup: some View {
        PreferenceSection(title: language.choose("备份与恢复", "Backup and restore"), detail: language.choose("保留设置与每日记录", "Keep settings and daily records")) {
            PreferenceRow(language.choose("自动备份", "Automatic backup"), detail: model.settings.backupDirectory ?? language.choose("未开启，可选择 iCloud Drive 文件夹", "Off. Choose a folder, including one in iCloud Drive")) {
                HStack(spacing: 8) {
                    if model.settings.backupDirectory != nil {
                        Button(language.choose("关闭", "Turn off")) { model.settings.backupDirectory = nil }.buttonStyle(QuietButtonStyle())
                    }
                    Button(language.choose("选择文件夹", "Choose folder"), action: model.chooseBackupDirectory).buttonStyle(QuietButtonStyle())
                }
            }
            Hairline()
            PreferenceRow(language.choose("数据文件", "Data files"), detail: language.choose("恢复前会先保存当前记录", "Current records are saved before restoring")) {
                HStack(spacing: 8) {
                    Button(language.choose("导出备份", "Export backup"), action: model.exportBackup).buttonStyle(QuietButtonStyle())
                    Button(language.choose("恢复备份", "Restore backup"), action: model.restoreBackup).buttonStyle(QuietButtonStyle())
                }
            }
            Text(language.choose("备份每 30 秒更新。iCloud Drive 同步由 macOS 管理，不包含手机提醒或多设备记录合并。", "Backups update every 30 seconds. macOS manages iCloud Drive syncing. Phone reminders and merging records across devices are not included."))
                .font(MujianStyle.caption).foregroundStyle(MujianStyle.secondary).fixedSize(horizontal: false, vertical: true).padding(.top, 8)
        }
    }
    private var reminderDetail: String {
        switch model.settings.reminderStyle {
        case .fullscreen: return language.choose("覆盖屏幕，显示休息倒计时", "Cover the screen with a break countdown")
        case .mini: return language.choose("显示小型休息窗口", "Show a small break window")
        case .notification: return language.choose("发送通知，继续记录用眼", "Send a notification and keep recording screen time")
        }
    }
    private func monitoringTitle(_ mode: MonitoringMode) -> String {
        switch mode {
        case .smart: return language.choose("智能检测", "Smart detection")
        case .continuous: return language.choose("阅读 / 观影", "Reading / video")
        }
    }
    private func reminderTitle(_ style: ReminderStyle) -> String {
        switch style {
        case .fullscreen: return language.choose("全屏休息", "Full screen")
        case .mini: return language.choose("迷你浮窗", "Mini window")
        case .notification: return language.choose("系统通知", "System notification")
        }
    }
    private func themeTitle(_ theme: AppTheme) -> String {
        switch theme {
        case .system: return language.choose("跟随系统", "Follow system")
        case .light: return language.choose("浅色", "Light")
        case .dark: return language.choose("深色", "Dark")
        }
    }
    private func hourPicker(_ title: String, _ binding: Binding<Int>) -> some View {
        Picker(title, selection: binding) { ForEach(0..<24) { Text(String(format: "%02d:00", $0)).tag($0) } }.labelsHidden().frame(width: 88)
    }
}

private struct PreferenceSection<Content: View>: View {
    let title: String
    let detail: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeading(title: title, detail: detail)
            VStack(alignment: .leading, spacing: 12) { content }
                .padding(24).background(MujianStyle.surface, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(MujianStyle.rule, lineWidth: 1))
        }
    }
}

private struct PreferenceRow<Control: View>: View {
    let title: String
    let detail: String
    @ViewBuilder var control: Control
    init(_ title: String, detail: String = "", @ViewBuilder control: () -> Control) { self.title = title; self.detail = detail; self.control = control() }
    var body: some View {
        HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(MujianStyle.body)
                if !detail.isEmpty { Text(detail).font(MujianStyle.caption).foregroundStyle(MujianStyle.secondary).fixedSize(horizontal: false, vertical: true) }
            }.frame(maxWidth: .infinity, alignment: .leading)
            control.font(.system(size: 13)).fixedSize(horizontal: true, vertical: false)
        }.padding(.vertical, 4).frame(minHeight: 40)
    }
}

private struct DayStyle: ButtonStyle {
    let selected: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.foregroundStyle(selected ? MujianStyle.ink : MujianStyle.muted)
            .background(selected ? MujianStyle.raised : .clear, in: RoundedRectangle(cornerRadius: 4))
            .overlay(alignment: .bottom) { if selected { Rectangle().fill(MujianStyle.accent).frame(width: 12, height: 2) } }
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

private struct NoRecords: View {
    let title: String
    let detail: String
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.system(size: 18, weight: .regular))
            Text(detail).font(MujianStyle.body).foregroundStyle(MujianStyle.secondary)
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

private func dayKey(_ date: Date) -> String {
    let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"; return formatter.string(from: date)
}
// Only format the tick label; chart values and record identities retain their full yyyy-MM-dd key.
private func shortDay(_ key: String, language: AppLanguage) -> String {
    let parser = DateFormatter()
    parser.locale = Locale(identifier: "en_US_POSIX")
    parser.calendar = Calendar(identifier: .gregorian)
    parser.dateFormat = "yyyy-MM-dd"
    guard let date = parser.date(from: key) else { return key }
    let formatter = DateFormatter()
    formatter.locale = language.locale
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.dateFormat = language.choose("MM/dd", "MMM d")
    return formatter.string(from: date)
}
private func weekday(_ day: Int, language: AppLanguage) -> String {
    guard (1...7).contains(day) else { return "" }
    let chinese = ["日", "一", "二", "三", "四", "五", "六"][day - 1]
    let formatter = DateFormatter(); formatter.locale = language.locale
    return language.choose(chinese, formatter.shortWeekdaySymbols[day - 1])
}
private func fullWeekday(_ day: Int, language: AppLanguage) -> String {
    guard (1...7).contains(day) else { return "" }
    let formatter = DateFormatter(); formatter.locale = language.locale
    return formatter.weekdaySymbols[day - 1]
}
