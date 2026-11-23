import Foundation

/// 任务页标题下方的鼓励语句（与安卓「主菜单鼓励语句」相同的内容，默认开启，每分钟换一句）。
enum MotivationalQuotes {
    static let enabledKey = "tasks.motivationalQuotes"

    static let chinese = [
        "Deadline 在追杀你！快跑💨", "任务完成度：1% → 99%🤯", "再拖？DDL要咬人了！🦖", "你离「完成」只差一个「提交」🚀",
        "提醒：别躺了，起来肝！🛏️→💻", "「先玩5分钟」→ 5小时😱", "你的待办列表：📜🔥（烧起来了）", "今日任务：活着 + 搞定它💪",
        "DDL越近，手速越快⚡", "「我明天做」→ 经典flag🚩", "任务完成 ✔️ 奖励：睡大觉！😴", "检测到：你在焦虑🌀",
        "别刷手机了！📱→❌", "「最后亿分钟」⌛", "任务堆积如山？愚公移山！⛰️", "DDL是你的敌人？不，是动力！💥",
        "「我好了」→「我装的」😏", "今日成就：没放弃！🏆", "建议：先做最难的！🎯", "完成它！然后大喊：Next！🎤",
    ]

    static let english = [
        "The deadline’s hunting you down! Run! 💨", "Progress: 1% → 99% 🤯", "Keep stalling? The deadline will bite! 🦖",
        "Only one click away from “done” 🚀", "Reminder: get up, stop doomscrolling, start working 🛏️→💻",
        "“Five more minutes” → five hours later 😱", "Your to-do list is on fire 📜🔥", "Today’s quest: survive + finish it 💪",
        "Deadline approaching = faster typing ⚡", "“I’ll do it tomorrow” → classic procrastination 🚩", "Task done ✔️ Reward: a nap 😴",
        "System alert: anxiety detected 🌀", "Put down your phone! 📱→❌", "The final countdown ⌛", "Tasks stacked up? Time to move mountains ⛰️",
        "Deadline isn’t your enemy, it’s your fuel 💥", "“I’m ready” → translation: “I’m faking it” 😏", "Achievement unlocked: didn’t give up 🏆",
        "Pro tip: start with the hardest one 🎯", "Done! Now yell: Next! 🎤",
    ]

    /// 按界面语言选择语句表。
    static var current: [String] {
        (Bundle.main.preferredLocalizations.first ?? "zh-Hans").hasPrefix("en") ? english : chinese
    }

    /// 每次启动从随机一句开始，之后每分钟换下一句。
    private static let offset = Int.random(in: 0..<1000)

    static func quote(at date: Date, from list: [String] = current) -> String {
        guard !list.isEmpty else { return "" }
        return list[(Int(date.timeIntervalSince1970 / 60) + offset) % list.count]
    }
}
