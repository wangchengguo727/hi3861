// entry/src/main/ets/pages/HomePage.ets
import http from '@ohos.net.http';
import { GlobalConfig } from '../utils/GlobalConfig';

class DeviceInfo {
  temperature: number = 0
  humidity: number = 0
  light_status: string = "OFF"
  smoke_level?: number = 0
  light_intensity?: number = 0
}

class ServerResponse {
  code: number = 0
  msg: string = ""
  result: DeviceInfo = new DeviceInfo()
}

@Component
export struct HomePage {
  @State temperature: number = 0
  @State humidity: number = 0
  @State lightIntensity: number = 0
  @State smokeLevel: number = 15
  // UI 状态
  @State currentMode: string = "智能托管"
  @State aiSuggestion: string = "正在唤醒大语言模型..."
  @State isConnected: boolean = false
  @State lastSyncTime: string = "--:--"
  @State isAiLoading: boolean = false
  @State breathingOpacity: number = 1.0
  @State isAiAutoControlEnabled: boolean = false
  private readonly BASE_INTERVAL: number = 3000;
  private readonly MAX_INTERVAL: number = 30000;
  @State currentInterval: number = 3000;
  private timerId: number = -1;
  private isDestroyed: boolean = false;

  // ✅ 新增：AI 冷却时间控制
  private lastAiRequestTime: number = 0;
  private readonly AI_COOLDOWN_MS: number = 3000; // 20秒请求一次 AI

  getTempColor(val: number): string {
    if (val >= 30) return '#FF5252'
    if (val < 15) return '#00BFA5'
    return '#FF9F43'
  }

  getHumColor(val: number): string {
    if (val >= 70) return '#00BFA5'
    if (val < 30) return '#FF9F43'
    return '#54A0FF'
  }

  getLightColor(val: number): string {
    if (val < 200) return '#9E9E9E'
    return '#FFC107'
  }

  getSmokeColor(val: number): string {
    if (val > 100) return '#FF5252'
    if (val > 50) return '#FF9F43'
    return '#4CAF50'
  }

  aboutToAppear() {
    this.isDestroyed = false;
    this.pollData();
  }

  aboutToDisappear() {
    this.isDestroyed = true;
    if (this.timerId !== -1) clearTimeout(this.timerId);
  }

  pollData() {
    if (this.isDestroyed) return;

    this.fetchData().then((isSuccess: boolean) => {
      if (this.isDestroyed) return;

      if (isSuccess) {
        this.currentInterval = this.BASE_INTERVAL;
      } else {
        this.currentInterval = Math.min(this.currentInterval * 2, this.MAX_INTERVAL);
      }

      this.timerId = setTimeout(() => {
        this.pollData();
      }, this.currentInterval);
    });
  }

  fetchData(): Promise<boolean> {
    return new Promise((resolve) => {
      let httpRequest = http.createHttp();

      httpRequest.request(
        `${GlobalConfig.getBaseUrl()}/get_data`,
        { method: http.RequestMethod.GET, readTimeout: 5000, connectTimeout: 5000 },
        (err, data) => {
          let isSuccess = false;

          if (!err && data.responseCode === 200) {
            try {
              let res = JSON.parse(data.result as string) as ServerResponse;
              if (res.code === 200) {
                this.temperature = res.result.temperature;
                this.humidity = res.result.humidity;
                this.lightIntensity = res.result.light_intensity !== undefined ? res.result.light_intensity : 0;
                this.smokeLevel = res.result.smoke_level !== undefined ? res.result.smoke_level : 15;

                this.isConnected = true;
                this.lastSyncTime = new Date().toLocaleTimeString('zh-CN', { hour12: false });

                // ✅ 核心修复点：增加了时间冷却判断
                let now = Date.now();
                if (!this.isAiLoading && (now - this.lastAiRequestTime > this.AI_COOLDOWN_MS)) {
                  this.lastAiRequestTime = now;
                  this.requestRealAiAnalysis();
                }

                isSuccess = true;
              }
            } catch (e) {
              console.error('JSON Error:', e);
            }
          } else {
            this.isConnected = false;
            // 不要因为网络波动立刻覆盖 AI 的话
            if (!this.aiSuggestion) {
              this.aiSuggestion = "网关离线，大模型已断开连接。";
            }
          }

          httpRequest.destroy();
          resolve(isSuccess);
        }
      );
    });
  }

  requestRealAiAnalysis() {
    this.isAiLoading = true;
    let httpRequest = http.createHttp();

    let promptText = "";
    if (this.isAiAutoControlEnabled) {
      promptText = "【AI自动托管模式】请用40个字以内评价当前环境。如果发现环境异常（如太热、太暗），请务必在返回的JSON中附带对应的 command 指令来自动控制设备！";
    } else {
      promptText = "【仅UI展示模式】请用40个字以内评价当前环境并给出建议。警告：绝对不要下发任何控制指令，JSON中的 command 字段必须严格为 null！";
    }

    httpRequest.request(
      `${GlobalConfig.getBaseUrl()}/chat`,
      {
        method: http.RequestMethod.POST,
        header: { 'Content-Type': 'application/json' },
        extraData: { "text": promptText },
        readTimeout: 15000,
        connectTimeout: 5000
      },
      (err, data) => {
        if (!err && data.responseCode === 200) {
          try {
            let res: Record<string, Object> = JSON.parse(data.result as string) as Record<string, Object>;
            if (res["reply"]) {
              this.aiSuggestion = res["reply"] as string;
            }
          } catch (e) {
            console.error('AI 响应解析失败');
          }
        } else {
          // 如果依然超时或429，友善提示
          console.error(`AI 请求失败，状态码: ${data?.responseCode}`);
        }
        this.isAiLoading = false;
        httpRequest.destroy();
      }
    );
  }

  build() {
    Column() {
      Row() {
        Column() {
          Text("智感 · 空间").fontSize(24).fontWeight(FontWeight.Bold).fontColor('#333333')
          Row() {
            Circle({ width: 6, height: 6 })
              .fill(this.isConnected ? '#00BFA5' : '#FF5252')
              .margin({ right: 6 })
            Text(this.isConnected ? `已连接 | 更新于 ${this.lastSyncTime}` : `连接断开 | 退避重试中 (${this.currentInterval/1000}s)`)
              .fontSize(12).fontColor('#888888')
          }.margin({ top: 4 })
        }
        .alignItems(HorizontalAlign.Start)

        Blank()

        Text("大语言模型在线")
          .fontSize(12).fontColor('#00BFA5').backgroundColor('#E0F2F1')
          .padding({ left: 8, right: 8, top: 4, bottom: 4 }).borderRadius(12)
          .opacity(this.breathingOpacity)
          .onAppear(() => {
            animateTo({
              duration: 1200,
              curve: Curve.EaseInOut,
              iterations: -1,
              playMode: PlayMode.Alternate
            }, () => {
              this.breathingOpacity = 0.3
            })
          })
      }.width('100%').padding(20).alignItems(VerticalAlign.Center)

      Scroll() {
        Column({ space: 15 }) {

          Column() {
            Row() {
              Image($r('app.media.icon_ai_sparkle'))
                .width(20).height(20).margin({ right: 5 })
                .fillColor(Color.White)
              Text("AI 实时分析").fontSize(16).fontWeight(FontWeight.Bold).fontColor(Color.White)

              LoadingProgress()
                .width(16).height(16).color(Color.White).margin({ left: 8 })
                .visibility(this.isAiLoading ? Visibility.Visible : Visibility.Hidden)

              Blank()

              Text("自动托管").fontSize(12).fontColor(Color.White).margin({ right: 6 })
              Toggle({ type: ToggleType.Switch, isOn: this.isAiAutoControlEnabled })
                .selectedColor('#00BFA5')
                .switchPointColor('#FFFFFF')
                .width(40).height(20)
                .onChange((isOn: boolean) => {
                  this.isAiAutoControlEnabled = isOn;
                })
            }
            .width('100%').margin({ bottom: 8 })

            Text(this.aiSuggestion)
              .fontSize(14).fontColor(Color.White).lineHeight(20).opacity(0.95)
              .width('100%')
              .animation({ duration: 500 })
          }
          .width('100%').padding(20).backgroundColor('#4A90E2').borderRadius(16)
          .shadow({ radius: 10, color: 'rgba(74, 144, 226, 0.3)', offsetY: 5 })

          Grid() {
            GridItem() { SensorCardItem({ title: '环境温度', value: this.temperature.toFixed(1), unit: '℃', themeColor: this.getTempColor(this.temperature), iconSource: $r('app.media.wendu_2'), progress: this.temperature / 40 }) }
            GridItem() { SensorCardItem({ title: '空气湿度', value: this.humidity.toFixed(0), unit: '%', themeColor: this.getHumColor(this.humidity), iconSource: $r('app.media.shidu_1'), progress: this.humidity / 100 }) }
            GridItem() { SensorCardItem({ title: '光照强度', value: this.lightIntensity.toFixed(0), unit: 'Lux', themeColor: this.getLightColor(this.lightIntensity), iconSource: $r('app.media.yanwu4'), progress: this.lightIntensity / 1000 }) }
            GridItem() { SensorCardItem({ title: '烟雾浓度', value: this.smokeLevel.toFixed(0), unit: 'ppm', themeColor: this.getSmokeColor(this.smokeLevel), iconSource: $r('app.media.yanwu4'), progress: this.smokeLevel / 200 }) }
          }
          .columnsTemplate('1fr 1fr').rowsTemplate('1fr 1fr').rowsGap(15).columnsGap(15).width('100%').height(320)

          Text("场景模式切换").fontSize(18).fontWeight(FontWeight.Bold).width('100%').margin({ top: 10 })
          Row({ space: 10 }) {
            this.ModeButton("智能托管")
            this.ModeButton("睡眠模式")
            this.ModeButton("离家防护")
          }
          .width('100%').justifyContent(FlexAlign.SpaceBetween)

          Blank().height(50)
        }
        .padding({ left: 20, right: 20 })
      }
      .layoutWeight(1)
    }
    .height('100%').backgroundColor('#F5F5F5')
  }

  @Builder ModeButton(modeName: string) {
    Column() {
      Text(modeName)
        .fontSize(14)
        .fontWeight(this.currentMode === modeName ? FontWeight.Bold : FontWeight.Normal)
        .fontColor(this.currentMode === modeName ? Color.White : '#666666')
    }
    .height(50).width('30%').justifyContent(FlexAlign.Center)
    .backgroundColor(this.currentMode === modeName ? '#4A90E2' : Color.White)
    .borderRadius(10).shadow({ radius: 3, color: 'rgba(0,0,0,0.1)', offsetY: 1 })
    .animation({ duration: 300 })
    .onClick(() => { this.currentMode = modeName })
  }
}

@Component
struct SensorCardItem {
  @Prop title: string; @Prop value: string; @Prop unit: string; @Prop themeColor: string; @Prop iconSource: Resource; @Prop progress: number;
  build() {
    Column() {
      Row() {
        Stack({ alignContent: Alignment.Center }) {
          Circle({ width: 32, height: 32 }).fill(this.themeColor).opacity(0.15).animation({ duration: 500 })
          Image(this.iconSource).width(18).height(18).objectFit(ImageFit.Contain).fillColor(this.themeColor).animation({ duration: 500 })
        }
        .margin({ right: 10 })
        Text(this.title).fontSize(14).fontColor('#666').fontWeight(FontWeight.Medium)
      }
      .width('100%').alignItems(VerticalAlign.Center).margin({ bottom: 15 })

      Row() {
        Text(this.value).fontSize(30).fontWeight(FontWeight.Bold).fontColor('#333').margin({ right: 4 })
        Text(this.unit).fontSize(14).fontColor('#999').margin({ bottom: 6 })
      }
      .alignItems(VerticalAlign.Bottom).width('100%').justifyContent(FlexAlign.Center)

      Blank()
      Stack({ alignContent: Alignment.Start }) {
        Row().width('100%').height(6).backgroundColor('#F0F0F0').borderRadius(3)
        Row().width(`${Math.min(this.progress, 1) * 100}%`).height(6).backgroundColor(this.themeColor).borderRadius(3).animation({ duration: 400, curve: Curve.EaseOut })
      }
      .width('100%').margin({ top: 10 })
    }
    .width('100%').height('100%').padding(15).backgroundColor(Color.White)
    .borderRadius(20).shadow({ radius: 10, color: 'rgba(0,0,0,0.05)', offsetY: 4 })
  }
}