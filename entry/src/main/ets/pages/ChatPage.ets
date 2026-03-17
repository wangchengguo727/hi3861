// entry/src/main/ets/pages/ChatPage.ets
import http from '@ohos.net.http';
import { GlobalConfig } from '../utils/GlobalConfig';
// ⚠️⚠️⚠️ 确认你的电脑 IP
const CHAT_API_URL = `${GlobalConfig.getBaseUrl()}/chat`;

export class Message {
  id: number;
  content: string;
  isUser: boolean;

  constructor(id: number, content: string, isUser: boolean) {
    this.id = id;
    this.content = content;
    this.isUser = isUser;
  }
}

@Component
export struct ChatPage {
  @State messages: Array<Message> = [
    new Message(1, "你好！我是你的家庭智能助手。你可以说'开灯'或者'我觉得有点热'。", false)
  ]
  @State inputText: string = ""
  @State isSending: boolean = false
  private scroller: Scroller = new Scroller()

  build() {
    Column() {
      // 1. 标题
      Row() {
        Text("AI 智能助手").fontSize(20).fontWeight(FontWeight.Bold).fontColor('#333')
        Blank()
        Button("清除").fontSize(12).height(28).backgroundColor('#F0F0F0').fontColor('#666')
          .onClick(() => { this.messages = [] })
      }
      .width('100%').padding(15).backgroundColor(Color.White)

      // 2. 消息列表
      List({ scroller: this.scroller }) {
        ForEach(this.messages, (item: Message) => {
          ListItem() {
            Row() {
              if (item.isUser) {
                // --- 用户消息 (保持不变) ---
                Blank()
                Text(item.content)
                  .padding(12)
                  .backgroundColor('#4A90E2')
                  .fontColor(Color.White)
                  .borderRadius(12)
                  .fontSize(15)
                  .constraintSize({ maxWidth: '75%' })
              } else {
                // --- AI 消息 (头像会顶格显示) ---
                Image($r('app.media.icon_robot_avatar'))
                  .width(36)
                  .height(36)
                  .margin({ right: 10, top: 2 }) // ✅ 微调：加一点 top 让它和气泡文字的第一行对齐
                  .borderRadius(18)
                  .backgroundColor('#E0E0E0')

                Text(item.content)
                  .padding(12)
                  .backgroundColor(Color.White)
                  .fontColor('#333')
                  .borderRadius(12)
                  .fontSize(15)
                  .constraintSize({ maxWidth: '75%' })
                  .lineHeight(20) // ✅ 建议：设置行高，让长文本阅读更舒服

                Blank()
              }
            }
            .width('100%')
            .padding({ left: 15, right: 15, top: 10, bottom: 10 })
            .alignItems(VerticalAlign.Top) // 🔥 关键修改：让整行元素顶部对齐
          }
        })
      }
      .layoutWeight(1)

      // 3. 输入框
      Row() {
        TextInput({ placeholder: "输入指令...", text: this.inputText })
          .height(40).layoutWeight(1).backgroundColor('#F5F5F5').borderRadius(20).padding({ left: 15 })
          .onChange((val) => { this.inputText = val })
          .onSubmit(() => { this.sendToAI() }) // 回车发送

        Button(this.isSending ? "..." : "发送")
          .height(36).width(70).margin({ left: 10 })
          .backgroundColor(this.inputText.length > 0 && !this.isSending ? '#4A90E2' : '#CCCCCC')
          .enabled(!this.isSending)
          .onClick(() => { this.sendToAI() })
      }
      .width('100%').padding(10).backgroundColor(Color.White)
    }
    .height('100%').backgroundColor('#F0F2F5')
  }

  sendToAI() {
    if (this.inputText.trim() === "" || this.isSending) return

    // 1. UI显示用户的话
    const userText = this.inputText
    this.messages.push(new Message(Date.now(), userText, true))
    this.inputText = ""
    this.isSending = true
    this.scroller.scrollEdge(Edge.Bottom)

    // 2. 发送 HTTP 请求给 Python
    let httpRequest = http.createHttp();
    httpRequest.request(
      CHAT_API_URL,
      {
        method: http.RequestMethod.POST,
        header: { 'Content-Type': 'application/json' },
        extraData: { "text": userText }, // 发送的内容
        readTimeout: 30000, // AI 思考需要时间，设长一点
        connectTimeout: 30000
      },
      (err, data) => {
        this.isSending = false
        if (!err && data.responseCode === 200) {
          try {
            // 解析 Python 返回的 JSON
            let res: Record<string, Object> = JSON.parse(data.result as string) as Record<string, Object>;
            // 显示 AI 的回复
            let reply = res["reply"] as string
            this.messages.push(new Message(Date.now(), reply, false))
          } catch (e) {
            this.messages.push(new Message(Date.now(), "数据解析错误", false))
          }
        } else {
          this.messages.push(new Message(Date.now(), "连接 AI 失败，请检查 Python", false))
        }
        this.scroller.scrollEdge(Edge.Bottom)
        httpRequest.destroy();
      }
    );
  }
}