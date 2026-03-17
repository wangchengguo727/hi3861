import promptAction from '@ohos.promptAction';
import http from '@ohos.net.http';
import { GlobalConfig } from '../utils/GlobalConfig';

const CONTROL_API_URL = `${GlobalConfig.getBaseUrl()}/control`;
// ✅ 关键点 1：新增获取数据的接口地址
const GET_DATA_URL = `${GlobalConfig.getBaseUrl()}/get_data`;

function sendControlCommand(cmd: string) {
  let httpRequest = http.createHttp();
  let requestData: Record<string, string> = { "command": cmd };
  httpRequest.request(
    CONTROL_API_URL,
    {
      method: http.RequestMethod.POST,
      header: { 'Content-Type': 'application/json' },
      extraData: requestData,
      readTimeout: 5000,
      connectTimeout: 5000
    },
    (err, data) => {
      if (!err && data.responseCode === 200) {
        console.info(`[指令发送成功] ${cmd}`);
      } else {
        console.error(`[指令发送失败] 错误: ${JSON.stringify(err)}`);
        promptAction.showToast({ message: '控制失败，请检查网络' });
      }
      httpRequest.destroy();
    }
  );
}

@Component
export struct ControlPage {
  @State isLightOn: boolean = false
  @State isAirConditionerOn: boolean = false
  @State fanSpeed: number = 0

  private timerId: number = -1; // 轮询定时器 ID

  // ✅ 关键点 2：每次进入这个页面，启动后台自动刷新
  aboutToAppear() {
    this.startPolling();
  }

  // ✅ 关键点 3：离开页面时销毁刷新，不浪费性能
  aboutToDisappear() {
    if (this.timerId !== -1) {
      clearInterval(this.timerId);
    }
  }

  // ✅ 关键点 4：每 3 秒去 Python 问一次“现在的状态是什么”
  startPolling() {
    this.syncStatus();
    this.timerId = setInterval(() => {
      this.syncStatus();
    }, 3000);
  }

  syncStatus() {
    let httpRequest = http.createHttp();
    httpRequest.request(
      GET_DATA_URL,
      { method: http.RequestMethod.GET, readTimeout: 5000, connectTimeout: 5000 },
      (err, data) => {
        if (!err && data.responseCode === 200) {
          try {
            let res: Record<string, Object> = JSON.parse(data.result as string) as Record<string, Object>;
            if (res["code"] === 200) {
              let state = res["result"] as Record<string, Object>;
              // 将获取到的最新状态覆写到 UI 上
              this.isLightOn = (state["light_status"] === 'ON');
              this.isAirConditionerOn = (state["air_status"] === 'ON');
              this.fanSpeed = state["fan_status"] as number;
            }
          } catch (e) {
            console.error('状态同步解析失败');
          }
        }
        httpRequest.destroy();
      }
    );
  }

  build() {
    Column() {
      Row() {
        Text("设备中心").fontSize(24).fontWeight(FontWeight.Bold).fontColor('#333333')
      }
      .width('100%').padding(20).backgroundColor(Color.White)

      Scroll() {
        Column({ space: 15 }) {
          DeviceSwitchCard({ name: "客厅主灯", isOn: $isLightOn })
          DeviceSwitchCard({ name: "空气净化器", isOn: $isAirConditionerOn })

          Column() {
            Row() {
              Text("风扇").fontSize(16).fontWeight(FontWeight.Bold)
              Blank()
              Text(this.fanSpeed === 0 ? "已关闭" : `${this.fanSpeed} 档`).fontSize(14).fontColor('#666666')
            }
            .width('100%').margin({ bottom: 15 })

            Row() {
              Button("关闭").onClick(() => {
                this.fanSpeed = 0;
                sendControlCommand("FanOff");
              })
                .backgroundColor(this.fanSpeed === 0 ? '#4A90E2' : '#F0F0F0')
                .fontColor(this.fanSpeed === 0 ? Color.White : '#333').height(30).fontSize(12)

              Button("1档").onClick(() => {
                this.fanSpeed = 1;
                sendControlCommand("FanSpeed1");
              })
                .backgroundColor(this.fanSpeed === 1 ? '#4A90E2' : '#F0F0F0')
                .fontColor(this.fanSpeed === 1 ? Color.White : '#333').height(30).fontSize(12)

              Button("2档").onClick(() => {
                this.fanSpeed = 2;
                sendControlCommand("FanSpeed2");
              })
                .backgroundColor(this.fanSpeed === 2 ? '#4A90E2' : '#F0F0F0')
                .fontColor(this.fanSpeed === 2 ? Color.White : '#333').height(30).fontSize(12)
            }
            .width('100%').justifyContent(FlexAlign.SpaceBetween)
          }
          .padding(15).backgroundColor(Color.White).borderRadius(16).width('100%')
          .shadow({ radius: 5, color: 'rgba(0,0,0,0.05)', offsetY: 2 })
        }
        .padding(20)
      }
      .layoutWeight(0)
    }
    .height('100%').backgroundColor('#F5F5F5')
  }
}

@Component
struct DeviceSwitchCard {
  name: string = ""
  @Link isOn: boolean

  build() {
    Row() {
      Column() {
        Text(this.name).fontSize(16).fontWeight(FontWeight.Bold)
        Text(this.isOn ? "已开启" : "已关闭")
          .fontSize(12)
          .fontColor(this.isOn ? '#4A90E2' : '#999999')
          .margin({ top: 4 })
          .animation({ duration: 300 })
      }
      .alignItems(HorizontalAlign.Start)

      Blank()

      Toggle({ type: ToggleType.Switch, isOn: this.isOn })
        .selectedColor('#4A90E2')
        .switchPointColor('#FFFFFF')
        .onChange((value: boolean) => {
          this.isOn = value
          if (this.name === "客厅主灯") {
            sendControlCommand(value ? "TurnOn" : "TurnOff");
          } else if (this.name === "空气净化器") {
            sendControlCommand(value ? "AirOn" : "AirOff");
          } else {
            promptAction.showToast({ message: `${this.name} ${value ? '已开启' : '已关闭'}` })
          }
        })
    }
    .width('100%')
    .padding(15)
    .backgroundColor(Color.White)
    .borderRadius(16)
    .shadow({ radius: 5, color: 'rgba(0,0,0,0.05)', offsetY: 2 })
  }
}