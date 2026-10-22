import Foundation

// 英文译文表：键是中文原文，值是英文。键里的 {} 是可变部分（模板），译文里的 {} 按顺序填回，也可用 {1}{2} 指定顺序。
// 其他语言由系统翻译在本机把这张表的中文键翻译出来，缺的项回退到英文。
enum L10nTable {
    static let en: [String: String] = {
        var d: [String: String] = [:]
        for line in raw.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let r = line.range(of: " ⇒ ") else { continue }
            let k = String(line[..<r.lowerBound]).replacingOccurrences(of: "\\n", with: "\n")
            let v = String(line[r.upperBound...]).replacingOccurrences(of: "\\n", with: "\n")
            if d[k] == nil { d[k] = v }
        }
        return d
    }()

    static let raw = #"""
完成 ⇒ Done
取消 ⇒ Cancel
保存 ⇒ Save
删除 ⇒ Delete
重命名 ⇒ Rename
复制 ⇒ Copy
分享 ⇒ Share
预览 ⇒ Preview
设置 ⇒ Settings
标题 ⇒ Title
添加 ⇒ Add
清除 ⇒ Clear
清空 ⇒ Clear
导入 ⇒ Import
运行 ⇒ Run
创建 ⇒ Create
搜索 ⇒ Search
范围 ⇒ Range
已连接 ⇒ Connected
未连接 ⇒ Not connected
结果 ⇒ Result
新对话 ⇒ New chat
搜索对话 ⇒ Search chats
知识库 ⇒ Knowledge base
工具箱 ⇒ Toolbox
任务 ⇒ Tasks
今日回顾 ⇒ Daily recap
进化 ⇒ Evolve
最近 ⇒ Recent
还没有对话 ⇒ No chats yet
没有匹配的对话 ⇒ No matching chats
重命名对话 ⇒ Rename chat
历史对话 ⇒ Earlier chat
早上好，我是{} ⇒ Good morning, I’m {}
中午好，我是{} ⇒ Good afternoon, I’m {}
下午好，我是{} ⇒ Good afternoon, I’m {}
晚上好，我是{} ⇒ Good evening, I’m {}
闹钟、提醒、文件转换、识别图片文字，都可以直接说。 ⇒ Alarms, reminders, file conversion and text recognition — just say it.
明早十点叫我起床 ⇒ Wake me up at 10 tomorrow morning
一周后下午三点提醒我交报告 ⇒ Remind me to submit the report at 3 PM in a week
每天早上八点总结我的待办 ⇒ Summarize my to-dos every morning at 8
把图片转成 PDF ⇒ Convert images to PDF
发消息给 {} ⇒ Message {}
发给「{}」的内容 ⇒ Content for “{}”
正在聆听，说完点右边按钮 ⇒ Listening… tap the button on the right when done
连接器 ⇒ Connectors
添加连接器… ⇒ Add connector…
添加与管理… ⇒ Add & manage…
系统时钟闹钟 ⇒ System Clock alarm
拍照 ⇒ Camera
照片 ⇒ Photos
文件 ⇒ Files
粘贴 ⇒ Paste
识别文字 ⇒ Recognize text
转成PDF ⇒ To PDF
转成PNG ⇒ To PNG
剪贴板里的图片无法读取 ⇒ Can’t read the image on the clipboard
剪贴板里的图片保存失败（{}） ⇒ Failed to save the clipboard image ({})
剪贴板是空的 ⇒ The clipboard is empty
无法打开文件：{} ⇒ Can’t open the file: {}
没有拿到照片 ⇒ Couldn’t get the photo
照片转换失败 ⇒ Photo conversion failed
照片保存失败（{}） ⇒ Failed to save the photo ({})
思考中… ⇒ Thinking…
分享对话 ⇒ Share chat
整段对话 ⇒ Whole chat
最近一轮 ⇒ Latest turn
发送对话链接 ⇒ Send chat link
重新生成并发送链接 ⇒ Regenerate and send link
正在生成链接… ⇒ Creating link…
链接 90 天有效，知道链接的人都能看到这段对话。 ⇒ The link is valid for 90 days. Anyone who has it can view this chat.
分享图片到微信、QQ、微博等 ⇒ Share image to WeChat, QQ, Weibo…
保存到相册 ⇒ Save to Photos
已保存到相册 ⇒ Saved to Photos
分享文字 ⇒ Share text
链接服务地址无效 ⇒ The link service address is invalid
没有可分享的内容 ⇒ Nothing to share
内容编码失败 ⇒ Failed to encode the content
今天生成的链接太多了，明天再试 ⇒ Too many links were created today. Try again tomorrow
链接服务返回异常（{}） ⇒ The link service returned an error ({})
连不上链接服务：{} ⇒ Can’t reach the link service: {}
对话分享 ⇒ SHARED CHAT
用户 ⇒ USER
把事情做得更清晰。 ⇒ A clearer way to get things done.
由「{}」生成 ⇒ Made with {}
开发者微信：TSTZ-M ⇒ Developer WeChat: TSTZ-M
搜索 · 思考 · 行动 ⇒ SEARCH · THINK · ACT
对话 ⇒ Chat
我 ⇒ Me
外观 ⇒ Appearance
主题 ⇒ Theme
跟随系统 ⇒ Follow system
浅色 ⇒ Light
深色 ⇒ Dark
保存对话记录 ⇒ Save chat history
回答风格 ⇒ Answer style
简洁 ⇒ Concise
详细 ⇒ Detailed
语音说完后自动发送 ⇒ Auto-send after voice input
本机模型 ⇒ On-device model
可用 ⇒ Available
未知 ⇒ Unknown
闹钟与连接 ⇒ Alarms & connections
系统时钟闹钟与自检 ⇒ System Clock alarms & self-test
灵动岛与实时活动 ⇒ Dynamic Island & Live Activities
在灵动岛显示思考、闹钟与任务倒计时 ⇒ Show thinking, alarm and task countdowns in the Dynamic Island
权限 ⇒ Permissions
通知、闹钟、照片、相机、麦克风等权限 ⇒ Notifications, alarms, photos, camera, microphone and more
数据 ⇒ Data
导出全部对话 ⇒ Export all chats
清空所有对话 ⇒ Delete all chats
清空知识库 ⇒ Clear knowledge base
关于 ⇒ About
版本 ⇒ Version
开发者微信 ⇒ Developer WeChat
清空所有对话？此操作无法撤销 ⇒ Delete all chats? This can’t be undone.
清空知识库？此操作无法撤销 ⇒ Clear the knowledge base? This can’t be undone.
对话记录 ⇒ Chat history
语言 ⇒ Language
应用语言 ⇒ App language
跨语言设置说明 ⇒ Language settings
切换后整个应用的界面、通知、灵动岛、分享页和助理回答都会使用所选语言。简体中文和 English 已内置，其他语言由系统翻译在本机完成，首次选择时需要下载语言包。 ⇒ The whole app — interface, notifications, Dynamic Island, share pages and the assistant’s replies — uses the language you choose. Simplified Chinese and English are built in; other languages are translated on-device by the system and need a one-time language pack download.
本机模型暂不支持该语言，助理回答会改用英语 ⇒ The on-device model doesn’t support this language yet; replies will be in English
正在准备语言包… ⇒ Preparing the language pack…
正在翻译界面：{} ⇒ Translating the interface: {}
语言包准备失败：{} ⇒ Couldn’t prepare the language pack: {}
该语言暂时使用英文界面 ⇒ This language temporarily uses the English interface
本机模型还没开启：请到 设置 → Apple 智能与 Siri，打开 Apple 智能 ⇒ The on-device model isn’t enabled. Go to Settings → Apple Intelligence & Siri and turn on Apple Intelligence
本机模型还在下载或准备中，请连上 Wi‑Fi 等几分钟再试 ⇒ The on-device model is still downloading or getting ready. Connect to Wi‑Fi and try again in a few minutes
这台设备不支持 Apple 智能，没法使用本机模型 ⇒ This device doesn’t support Apple Intelligence, so the on-device model can’t be used
本机模型暂时不可用（{}） ⇒ The on-device model is temporarily unavailable ({})
这个话题触发了系统模型的安全限制，我没法回答 ⇒ This topic triggered the system model’s safety limits, so I can’t answer it
换个说法或说明正当用途再试 ⇒ Try rewording it or explain the legitimate purpose
系统模型暂不支持这种语言或地区设置，请换个说法 ⇒ The system model doesn’t support this language or region setting yet. Try rephrasing
本机模型资源还没准备好，请稍等几分钟再试 ⇒ The on-device model assets aren’t ready yet. Try again in a few minutes
这次没能完成（{}） ⇒ Couldn’t finish this time ({})
可以点「重新生成」，或换个说法 ⇒ Tap “Regenerate” or try rewording
已停止 ⇒ Stopped
已停止。 ⇒ Stopped.
模型没有返回内容 ⇒ The model returned nothing
文档 ⇒ Documents
知识片段 ⇒ Knowledge chunks
描述你要找的内容 ⇒ Describe what you’re looking for
我的文档 ⇒ My documents
还没有文档，点右上角「导入」 ⇒ No documents yet. Tap “Import” at the top right
{} 个片段 ⇒ {} chunks
已授权的文件夹（助理可查找、读取） ⇒ Authorized folders (the assistant can search and read them)
授权文件夹 ⇒ Authorize a folder
已授权 {} 个文件夹 ⇒ Authorized {} folder(s)
已导入 {} 个文档 ⇒ Imported {} document(s)
我的记忆 ⇒ My memories
进化提炼的记忆 ⇒ Memories from evolving
脚本技能 · {} ⇒ Script skill · {}
文件转换 ⇒ File conversion
图片、PDF、表格、视频互相转换 ⇒ Convert between images, PDFs, spreadsheets and videos
脚本技能 ⇒ Script skills
一句话生成脚本，自动测试并运行 ⇒ Describe a script in one sentence; it’s tested and run automatically
连接快捷指令、Scriptable 和各种接口 ⇒ Connect Shortcuts, Scriptable and web APIs
快捷指令 ⇒ Shortcuts
把本 App 的动作加入系统快捷指令 ⇒ Add this app’s actions to Shortcuts
把闹钟写进「时钟」，并自检内置闹钟 ⇒ Write alarms into Clock and self-test built-in alarms
用一句话创建 ⇒ Create with one sentence
例如：把输入的文字倒过来 ⇒ e.g. Reverse the input text
创建并运行 ⇒ Create and run
准备中… ⇒ Preparing…
已创建「{}」并运行成功 ⇒ Created “{}” and ran it successfully
运行结果：{} ⇒ Result: {}
没能生成可运行的脚本（{}），请换个描述再试一次 ⇒ Couldn’t produce a runnable script ({}). Try rewording it
我的技能 ⇒ My skills
还没有技能，先在上面创建一个 ⇒ No skills yet. Create one above
导入技能包 ⇒ Import skill pack
输入内容 ⇒ Input
可以留空 ⇒ Optional
运行结果 ⇒ Result
给其他应用调用 ⇒ For other apps
复制调用链接 ⇒ Copy call link
已复制调用链接 ⇒ Call link copied
删除这个技能 ⇒ Delete this skill
连接本机已有的应用或网络接口，让助理在对话里直接调用，例如说「用快捷指令 XX 处理这段话」。 ⇒ Connect apps already on this device or web APIs so the assistant can call them in chat, e.g. say “use the shortcut XX to process this text”.
还没有连接器，点右上角添加 ⇒ No connectors yet. Tap + to add one
添加连接器 ⇒ Add connector
类型 ⇒ Type
Scriptable 脚本 ⇒ Scriptable script
其他 App ⇒ Other app
网络接口 ⇒ Web API
名称（对话里用它来调用） ⇒ Name (used to call it in chat)
例如：整理文字 ⇒ e.g. Tidy text
快捷指令的名称 ⇒ Shortcut name
Scriptable 脚本的名称 ⇒ Scriptable script name
目标应用的网址，用 [内容] 代表传入的文字 ⇒ URL of the target app; write [内容] where the input text goes
接口地址，用 [内容] 代表传入的文字 ⇒ API address; write [内容] where the input text goes
请输入 ⇒ Enter
请求方式 ⇒ Request method
方式 ⇒ Method
请求头（每行一项，写成 名称: 值） ⇒ Headers (one per line, as Name: Value)
发送内容（用 [内容] 代表传入的文字） ⇒ Body (write [内容] where the input text goes)
传入内容 ⇒ Input to pass
调用 ⇒ Call
调用中… ⇒ Calling…
返回结果 ⇒ Response
打开快捷指令 ⇒ Open Shortcuts
新建快捷指令 ⇒ New shortcut
本 App 提供的动作 ⇒ Actions provided by this app
询问助理 ⇒ Ask the assistant
把一句话交给助理，拿到回答 ⇒ Hand a sentence to the assistant and get an answer
检索知识库 ⇒ Search the knowledge base
按语义查找知识库内容 ⇒ Find knowledge-base content by meaning
加入知识库 ⇒ Add to the knowledge base
把文字存进知识库 ⇒ Save text to the knowledge base
运行脚本技能 ⇒ Run a script skill
运行你创建的脚本并返回结果 ⇒ Run a script you created and return the result
N 分钟后提醒 ⇒ Remind me in N minutes
几分钟后发送通知提醒 ⇒ Send a notification reminder after a few minutes
怎么用 ⇒ How to use
1. 打开快捷指令，点右上角加号新建\n2. 点「添加操作」，搜索 {}\n3. 选择上面的动作，再接上你想要的步骤\n4. 在「自动化」里设置时间，就能定时自动运行 ⇒ 1. Open Shortcuts and tap + at the top right\n2. Tap “Add Action” and search for {}\n3. Pick an action above, then add the steps you want\n4. Set a time under “Automation” to run it on a schedule
让其他应用调用本 App ⇒ Let other apps call this app
复制「提问」链接 ⇒ Copy the “Ask” link
已复制提问链接 ⇒ “Ask” link copied
复制「运行脚本」链接 ⇒ Copy the “Run script” link
已复制运行链接 ⇒ “Run script” link copied
点一个连接器，回到聊天后输入内容发送，结果直接显示在对话里。也可以直接说「用 币安价格 查 BTCUSDT」。 ⇒ Tap a connector, go back to the chat and send some input; the result appears in the conversation. You can also just say “use Binance Price to check BTCUSDT”.
还没有连接器，从下面一键添加 ⇒ No connectors yet. Add one below
测试一下 ⇒ Test it
一键添加（免费，无需密钥） ⇒ One-tap add (free, no key needed)
已添加 ⇒ Added
高级 ⇒ Advanced
自定义与管理（快捷指令、Scriptable、网络接口） ⇒ Customize & manage (Shortcuts, Scriptable, web APIs)
复制 Scriptable 回调脚本模板 ⇒ Copy the Scriptable callback template
已复制 Scriptable 回调模板。新建一个 Scriptable 脚本粘贴进去，再在这里添加同名的「Scriptable 脚本」连接器，运行结果会自动回到对话。 ⇒ Scriptable callback template copied. Create a Scriptable script, paste it in, then add a “Scriptable script” connector here with the same name; results come back to the chat automatically.
「{}」测试结果：\n{} ⇒ “{}” test result:\n{}
现货最新价，输入交易对 ⇒ Latest spot price; enter a trading pair
多个币种美元价与 24 小时涨跌 ⇒ USD prices and 24h change for several coins
搜链上代币：价格、24h 涨跌、流动性、FDV（取流动性最大的 5 个池子） ⇒ Search on-chain tokens: price, 24h change, liquidity, FDV (top 5 pools by liquidity)
城市当前天气 ⇒ Current weather for a city
交易对，如 BTCUSDT ⇒ Trading pair, e.g. BTCUSDT
币种全名小写，用逗号分隔，如 bitcoin,solana ⇒ Lowercase coin IDs separated by commas, e.g. bitcoin,solana
代币名称或合约地址 ⇒ Token name or contract address
城市名，如 上海 ⇒ City name, e.g. Shanghai
没有找到名为「{}」的连接器 ⇒ No connector named “{}” was found
接口地址无效，请检查连接器里的地址 ⇒ The API address is invalid. Check the address in the connector
接口返回错误（{}）：{} ⇒ The API returned an error ({}): {}
接口返回了空内容（{}） ⇒ The API returned empty content ({})
没有网络，请检查网络后再试 ⇒ No network. Check your connection and try again
请求超时。这个接口在当前网络下可能需要代理才能访问 ⇒ The request timed out. This API may need a proxy on your current network
接口调用失败：{} ⇒ API call failed: {}
目标地址无效，请检查连接器设置 ⇒ The target address is invalid. Check the connector settings
无法打开，请确认对应 App 已安装 ⇒ Can’t open it. Make sure the app is installed
已打开「{}」对应的 App ⇒ Opened the app for “{}”
已交给「{}」处理，完成后会自动回到这里并显示结果 ⇒ Handed to “{}”; when it finishes you’ll come back here and see the result
「{}」已取消 ⇒ “{}” was cancelled
「{}」运行失败 ⇒ “{}” failed to run
「{}」运行失败：{} ⇒ “{}” failed to run: {}
请确认快捷指令或脚本的名称与连接器里填的一致 ⇒ Make sure the shortcut or script name matches the one in the connector
「{}」已运行完成（没有返回内容） ⇒ “{}” finished (no content returned)
「{}」返回： ⇒ “{}” returned:
闹钟和定时任务都在这里。右侧开关随时开启或关闭，关闭后不再响铃或提醒，记录会保留。 ⇒ Alarms and scheduled tasks live here. Use the switch on the right to turn them on or off; turned-off items stop ringing or reminding but stay in the list.
新建 ⇒ New
例：明早十点叫我起床 ⇒ e.g. Wake me up at 10 tomorrow morning
创建中… ⇒ Creating…
没有闹钟 ⇒ No alarms
闹钟 · {}/{} 个开启 ⇒ Alarms · {}/{} on
没有定时任务 ⇒ No scheduled tasks
已为 {} 个任务准备好内容并安排了通知 ⇒ Prepared content and scheduled notifications for {} task(s)
没有需要准备的任务 ⇒ No tasks need preparing
正在准备… ⇒ Preparing…
立即准备并安排通知 ⇒ Prepare and schedule notifications now
定时任务 · {}/{} 个开启 ⇒ Scheduled tasks · {}/{} on
进化与记忆 ⇒ Evolution & memory
已写入系统「时钟」，请在「时钟」App 里开关 ⇒ Written to the system Clock app; turn it on or off there
已响过 ⇒ Already rang
内置闹钟：到点响铃，静音和专注模式下也会响 ⇒ Built-in alarm: rings on time, even in silent and Focus modes
已完成 ⇒ Completed
已关闭 ⇒ Off
已开启 ⇒ On
内容：{} ⇒ Content: {}
提前由本机模型准备内容，到点通知送达 ⇒ The on-device model prepares the content ahead of time; a notification delivers it on time
到点发送通知提醒 ⇒ Sends a reminder notification on time
已准备：{} ⇒ Prepared: {}
没能识别时间，请说得具体一些，比如「明早十点叫我起床」 ⇒ Couldn’t work out the time. Be more specific, e.g. “wake me up at 10 tomorrow morning”
助理会从对话里提炼你的长期偏好并存进知识库；对话足够多时，还会谨慎改进自己的系统提示（可随时回滚）。聊几轮后自动进行，也可以手动触发。 ⇒ The assistant distills your long-term preferences from chats into the knowledge base and, with enough conversations, carefully improves its own system prompt (you can roll back anytime). It runs automatically after a few turns, or you can trigger it manually.
上次进化：{} ⇒ Last evolution: {}
尚未进行 ⇒ Not yet
立即进化 ⇒ Evolve now
正在进化… ⇒ Evolving…
每次进化都做了什么 ⇒ What each evolution did
还没有进化记录。多聊几轮会自动进化，也可以点上面的「立即进化」。 ⇒ No evolution records yet. It happens automatically after a few more turns, or tap “Evolve now” above.
系统提示版本 ⇒ System prompt versions
第 {} 版（当前） ⇒ Version {} (current)
第 {} 版 ⇒ Version {}
回滚到这一版 ⇒ Roll back to this version
当前使用默认提示 ⇒ Using the default prompt
分析了 {} 条新对话；新增 {} 条记忆；提示词保持不变 ⇒ Analyzed {} new message(s); added {} memory item(s); prompt unchanged
分析了 {} 条新对话；新增 {} 条记忆；系统提示已更新到第 {} 版 ⇒ Analyzed {} new message(s); added {} memory item(s); system prompt updated to version {}
还没有足够的新对话可供进化 ⇒ Not enough new conversations to evolve yet
进化时模型没有返回结果，稍后再试 ⇒ The model returned nothing while evolving. Try again later
苹果不允许 App 直接往「时钟」里写闹钟，唯一的官方通道是「快捷指令」里的「创建闹钟」。按下面做一次，以后说一句话就会写进时钟。 ⇒ Apple doesn’t let apps write alarms into the Clock app directly; the only official route is the “Create Alarm” action in Shortcuts. Do the steps below once, and from then on a single sentence writes to Clock.
闹钟方式 ⇒ Alarm mode
自动 ⇒ Automatic
只用内置 ⇒ Built-in only
已连接时钟时写入「时钟」App；同时先登记一个内置闹钟作保底，写入成功后自动取消，不会重复响。 ⇒ When Clock is connected, alarms are written to the Clock app; a built-in alarm is registered first as a backup and cancelled automatically once the write succeeds, so it never rings twice.
只用内置闹钟：会响铃，静音和专注模式下也响，但不出现在「时钟」列表里。 ⇒ Built-in alarms only: they ring, even in silent and Focus modes, but don’t appear in the Clock list.
做法同上，名称改成「TSTZ每日闹钟」，并在「创建闹钟」里把重复选成每天（周日到周六全选）。 ⇒ Same as above, but name it “TSTZ每日闹钟” and set Repeat to every day (Sunday to Saturday) in “Create Alarm”.
1. 点「新建快捷指令」，再点「添加操作」，搜索「创建闹钟」并选中\n2. 点其中的「时间」，选「快捷指令输入」\n3. 把名称改成「TSTZ闹钟」（先点下面的复制），点完成\n4. 回到这里点「测试」 ⇒ 1. Tap “New Shortcut”, then “Add Action”, search for “Create Alarm” and select it\n2. Tap its “Time” and choose “Shortcut Input”\n3. Rename it to “TSTZ闹钟” (tap Copy below first) and tap Done\n4. Come back here and tap “Test”
复制快捷指令名称 ⇒ Copy shortcut name
测试（写入一个约 2 分钟后的闹钟） ⇒ Test (writes an alarm about 2 minutes from now)
已复制名称「{}」 ⇒ Copied the name “{}”
每日闹钟（「每天早上七点叫我起床」） ⇒ Daily alarm (“wake me up at 7 every morning”)
一次性闹钟（「明早七点叫我起床」） ⇒ One-time alarm (“wake me up at 7 tomorrow morning”)
内置闹钟自检 ⇒ Built-in alarm self-test
测试内置闹钟（约 1 分钟后响） ⇒ Test the built-in alarm (rings in about 1 minute)
最近一次结果 ⇒ Latest result
测试闹钟 ⇒ Test alarm
闹钟权限：{}；系统已登记 {} 个内置闹钟 ⇒ Alarm permission: {}; {} built-in alarm(s) registered with the system
已允许 ⇒ Allowed
已拒绝（请到 设置 → {} 开启闹钟） ⇒ Denied (go to Settings → {} and turn on Alarms)
还没询问 ⇒ Not asked yet
今天 ⇒ Today
明天 ⇒ Tomorrow
后天 ⇒ Day after tomorrow
每天 ⇒ Daily
每周 ⇒ Weekly
闹钟 ⇒ Alarm
提醒 ⇒ Reminder
日程 ⇒ Event
定时任务 ⇒ Scheduled task
停止 ⇒ Stop
补跑：{} ⇒ Catch-up: {}
{}（仅通知） ⇒ {} (notification only)
每日 ⇒ daily
一次性 ⇒ one-time
这个时间已经过了，换一个时间试试 ⇒ That time has already passed. Try another time
这个闹钟的时间已经过了，请重新创建一个 ⇒ This alarm’s time has already passed. Please create a new one
闹钟已设置：{}「{}」 ⇒ Alarm set: {} “{}”
到点会像系统闹钟一样响铃，静音和专注模式下也会响 ⇒ It rings like a system alarm, even in silent and Focus modes
正在写入系统「时钟」，完成后会提示 ⇒ Writing it to the system Clock app; you’ll be notified when done
它不在「时钟」App 的列表里；点输入框左边「+」→「系统时钟闹钟」连接一次，以后就会写进时钟 ⇒ It isn’t in the Clock app’s list. Tap “+” next to the input box → “System Clock alarm” to connect once; after that alarms are written to Clock
内置闹钟不可用（{}），已改为写入系统「时钟」，完成后会提示 ⇒ The built-in alarm is unavailable ({}); writing to the system Clock app instead, you’ll be notified when done
闹钟没能设置成响铃：{} ⇒ Couldn’t set the alarm to ring: {}
已先用通知提醒你，到点只会弹通知、不会响铃 ⇒ You’ll get a notification instead; it will only pop up, not ring
系统没有登记这个闹钟 ⇒ The system didn’t register this alarm
没有闹钟权限，请到 设置 → {} 里允许闹钟 ⇒ No alarm permission. Go to Settings → {} and allow Alarms
重新开启失败：{} ⇒ Couldn’t turn it back on: {}
提醒已设置：{}「{}」，已写入系统提醒事项 ⇒ Reminder set: {} “{}”, saved to the Reminders app
提醒已设置：{}「{}」，将以通知提醒你 ⇒ Reminder set: {} “{}”, you’ll be reminded by notification
日程已添加：{}「{}」，提前 10 分钟提醒 ⇒ Event added: {} “{}”, with a reminder 10 minutes before
没有日历权限，请到 设置 → {} 里允许日历 ⇒ No Calendar permission. Go to Settings → {} and allow Calendars
日程添加失败：{} ⇒ Couldn’t add the event: {}
定时任务已创建：{}「{}」 ⇒ Scheduled task created: {} “{}”
到点前我会先准备好内容，再用通知送达 ⇒ I’ll prepare the content ahead of time and deliver it by notification
已写入系统「时钟」（{}闹钟，{}） ⇒ Written to the system Clock app ({} alarm, {})
请打开「时钟」App 确认出现了这条闹钟，确认后可以删除它 ⇒ Open the Clock app to confirm the alarm appears, then you can delete it
已写入系统「时钟」：{} ⇒ Written to the system Clock app: {}
内置备份闹钟已取消，不会重复响铃 ⇒ The built-in backup alarm was cancelled, so it won’t ring twice
没能写入系统「时钟」：{} ⇒ Couldn’t write to the system Clock app: {}
你取消了运行 ⇒ You cancelled the run
快捷指令「{}」运行失败，可能名称不一致或还没创建 ⇒ The shortcut “{}” failed to run; the name may not match or it hasn’t been created
请按「系统时钟闹钟」页的步骤检查 ⇒ Please follow the steps on the “System Clock alarm” page to check
内置闹钟已保留，到点照样会响 ⇒ The built-in alarm is kept and will still ring on time
请在「+」→「系统时钟闹钟」检查连接 ⇒ Check the connection under “+” → “System Clock alarm”
第 {} 张： ⇒ Image {}:
没有识别到文字 ⇒ No text was recognized
可以换一张更清晰的图，或直接告诉我要对这张图做什么 ⇒ Try a clearer image, or just tell me what to do with it
收到 {} 张图片 ⇒ Received {} image(s)
我能识别图中的文字和大致类别，看不到画面细节 ⇒ I can read the text and rough category of an image, but I can’t see fine visual details
类别：{} ⇒ Category: {}
图中没有识别到文字 ⇒ No text was recognized in the image
图中文字：{} ⇒ Text in the image: {}
可以点输入框上方的「识别文字」「转成PDF」「转成PNG」，或直接告诉我要对这张图做什么 ⇒ Tap “Recognize text”, “To PDF” or “To PNG” above the input box, or just tell me what to do with this image
做不到：iOS 不允许一个 App 自动点击或操作别的 App（点赞、关注、刷视频都不行），快捷指令也一样 ⇒ Not possible: iOS doesn’t let one app tap or control other apps automatically (liking, following, scrolling videos — none of it), and Shortcuts can’t either
脚本技能只能处理文字、读网页、查知识库，比如整理文案、提取网页要点、批量改写 ⇒ Script skills can only handle text, read web pages and query the knowledge base — e.g. tidy copy, extract page highlights, batch rewrite
想做其中一种，直接告诉我 ⇒ If you want one of those, just tell me
正在编写脚本… ⇒ Writing the script…
已创建脚本技能「{}」，试运行结果： ⇒ Created the script skill “{}”. Trial run result:
以后说「运行 {}」，或到 工具箱 → 脚本技能 里使用 ⇒ From now on say “run {}”, or use it under Toolbox → Script skills
没能生成可运行的脚本（{}） ⇒ Couldn’t produce a runnable script ({})
请把需求说具体一点：输入是什么、希望输出什么 ⇒ Please be more specific: what is the input and what output do you want
转换完成，共 {} 个文件，点下方文件可预览或分享 ⇒ Conversion complete: {} file(s). Tap a file below to preview or share
转换失败：{} ⇒ Conversion failed: {}
识别图中文字 ⇒ Recognize text in the image
图片 ⇒ Image
PDF 文档 ⇒ PDF document
表格数据 ⇒ Spreadsheet data
文本文档 ⇒ Text document
视频 ⇒ Video
音频 ⇒ Audio
文件不存在 ⇒ File not found
空文件 ⇒ Empty file
这张图片无法读取 ⇒ This image can’t be read
从相册选择照片或视频 ⇒ Choose a photo or video from Photos
从「文件」App 选择 ⇒ Choose from the Files app
正在读取… ⇒ Reading…
已选择：{} ⇒ Selected: {}
转换成 ⇒ Convert to
转换中… ⇒ Converting…
开始转换 ⇒ Start converting
转换结果 ⇒ Conversion results
存入相册 ⇒ Save to Photos
支持图片、PDF、表格（CSV、JSON、Markdown、网页）、文本、视频互相转换，也能识别图片中的文字。 ⇒ Converts between images, PDFs, spreadsheets (CSV, JSON, Markdown, web pages), text and videos, and can recognize text in images.
JPG 图片 ⇒ JPG image
PNG 图片 ⇒ PNG image
HEIC 图片 ⇒ HEIC image
TIFF 图片 ⇒ TIFF image
GIF 图片 ⇒ GIF image
BMP 图片 ⇒ BMP image
文字 ⇒ Text
CSV 表格 ⇒ CSV table
TSV 表格 ⇒ TSV table
Markdown ⇒ Markdown
网页 ⇒ Web page
MP4 视频 ⇒ MP4 video
MOV 视频 ⇒ MOV video
压缩视频 ⇒ Compressed video
视频读取失败，请换一个再试 ⇒ Couldn’t read the video. Try another one
视频读取失败：{} ⇒ Couldn’t read the video: {}
图片读取失败，请换一张再试 ⇒ Couldn’t read the image. Try another one
图片保存失败（{}） ⇒ Failed to save the image ({})
这张图片的格式无法识别 ⇒ The format of this image isn’t recognized
图片读取失败：{} ⇒ Couldn’t read the image: {}
文件读取失败 ⇒ Couldn’t read the file
「{}」读取失败。如果它在 iCloud 里，请先在「文件」App 里下载到本机。 ⇒ Couldn’t read “{}”. If it’s in iCloud, download it to this device in the Files app first.
「{}」是空文件。 ⇒ “{}” is an empty file.
「{}」不是有效的图片。 ⇒ “{}” isn’t a valid image.
暂不支持 .{} 转 .{} ⇒ Converting .{} to .{} isn’t supported yet
无法读取图片 ⇒ Can’t read the image
编码失败 ⇒ Encoding failed
不支持写入 {} ⇒ Writing {} isn’t supported
图片不能转成 {} ⇒ Images can’t be converted to {}
无法打开 PDF ⇒ Can’t open the PDF
PDF 可转成 png、jpg、txt ⇒ PDFs can be converted to png, jpg or txt
视频可转成 mp4、mov、m4a、jpg 或 压缩 ⇒ Videos can be converted to mp4, mov, m4a, jpg or compressed
无法创建导出任务 ⇒ Can’t create the export task
文件为空或无法读取 ⇒ The file is empty or can’t be read
没有识别到表格 ⇒ No table was recognized
表格可转成 csv、json、md、html、tsv、txt、pdf ⇒ Tables can be converted to csv, json, md, html, tsv, txt or pdf
文本可转成 txt、md、html、pdf ⇒ Text can be converted to txt, md, html or pdf
选择照片 ⇒ Choose photos
已选 {} 张 ⇒ {} selected
处理中… ⇒ Working…
正在请求相册权限… ⇒ Requesting photo access…
现在只授权了部分照片，想看到全部请改为「所有照片」 ⇒ Only some photos are shared. To see all of them, switch to “All Photos”
选择更多照片 ⇒ Select more photos
去设置改为全部 ⇒ Change to all in Settings
没有相册权限 ⇒ No photo access
到 设置 → {} → 照片，选择「所有照片」，就能看到整个相册。 ⇒ Go to Settings → {} → Photos and choose “All Photos” to see your whole library.
打开设置 ⇒ Open Settings
改用系统选择器（无需授权） ⇒ Use the system picker instead (no permission needed)
图片读取失败（{}）。可以先在相册里点开这张图让它下载完整，再试一次。 ⇒ Couldn’t read the image ({}). Open it in Photos first so it finishes downloading, then try again.
有 {} 张没能读取（{}） ⇒ {} image(s) couldn’t be read ({})
汇总今天本机允许读取的日历、提醒事项、相册、任务和对话，再由本机模型写成一份总结。 ⇒ Gathers today’s calendar, reminders, photos, tasks and chats that this device allows, then the on-device model writes a summary.
今天自动读取到的 ⇒ Read automatically today
重新读取 ⇒ Read again
屏幕使用时间与通知 ⇒ Screen Time & notifications
iOS 不允许任何 App 直接读取屏幕使用时间和其他 App 的通知。办法：在「设置 → 屏幕使用时间 → 查看所有活动」截图，或截一张通知中心，在这里导入，由本机识别文字后一起总结。 ⇒ iOS doesn’t let any app read Screen Time or other apps’ notifications directly. Workaround: take a screenshot of “Settings → Screen Time → See All Activity” (or of Notification Center), import it here, and the device reads the text and includes it in the summary.
导入截图 ⇒ Import screenshots
正在识别文字… ⇒ Recognizing text…
已识别 {} 张截图 ⇒ Recognized {} screenshot(s)
生成今日总结 ⇒ Generate today’s summary
正在总结… ⇒ Summarizing…
存入知识库 ⇒ Save to knowledge base
已存入知识库 ⇒ Saved to knowledge base
这次没能生成（{}），请再试一次。 ⇒ Couldn’t generate it this time ({}). Please try again.
模型没有返回内容，请再试一次。 ⇒ The model returned nothing. Please try again.
日历 ⇒ Calendar
今天没有日程 ⇒ no events today
全天 ⇒ All day
日历：共 {} 项：{} ⇒ Calendar: {} item(s): {}
提醒事项：今天及逾期未完成 {} 项{}；今天已完成 {} 项{} ⇒ Reminders: {} open or overdue{}; {} completed today{}
（{}） ⇒  ({})
相册：今天拍了 {} 张照片{}{} ⇒ Photos: {} taken today{}{}
、{} 段视频 ⇒ , {} video(s)
，时间 {} 到 {} ⇒ , from {} to {}
相册：今天没有新照片 ⇒ Photos: no new photos today
助理：今天和助理对话 {} 次 ⇒ Assistant: {} chat(s) with the assistant today
定时任务：今天有 {} 个：{} ⇒ Scheduled tasks: {} today: {}
闹钟：今天有 {} 个：{} ⇒ Alarms: {} today: {}
分享 ⇒ Share
预览 ⇒ Preview
对话中 ⇒ In chat
聊听中 ⇒ Listening
思考中 ⇒ Thinking
正在搜索网页 ⇒ Searching the web
正在执行任务 ⇒ Executing task
任务已完成 ⇒ Task completed
正在处理文件 ⇒ Processing files
正在编写脚本 ⇒ Writing a script
聆听中 ⇒ Listening
语音识别暂时不可用，请检查网络，或在 设置 → 通用 → 键盘 里开启听写 ⇒ Speech recognition is unavailable right now. Check your network, or turn on Dictation in Settings → General → Keyboard
请在 设置 → {} 里允许语音识别 ⇒ Please allow Speech Recognition in Settings → {}
请在 设置 → {} 里允许麦克风 ⇒ Please allow the Microphone in Settings → {}
没有听清，请靠近一点再说一次 ⇒ Couldn’t hear clearly. Move closer and try again
无法启动麦克风：{} ⇒ Can’t start the microphone: {}
没有听到声音，请再试一次 ⇒ Didn’t hear anything. Please try again
"""#
}
