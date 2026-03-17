// entry/src/main/ets/pages/Index.ets
import { HomePage } from './HomePage';
import { ControlPage } from './ControlPage';
import { ChatPage } from './ChatPage';

@Entry
@Component
struct Index {
  @State currentIndex: number = 0
  private controller: TabsController = new TabsController()

  build() {
    Column() {
      Tabs({ barPosition: BarPosition.End, controller: this.controller }) {
        // --- Tab 1: 首页 ---
        TabContent() {
          HomePage()
        }
        // 传入普通状态和选中状态的图片资源
        .tabBar(this.TabBuilder('主页', 0, $r('app.media.ic_home_normal'), $r('app.media.ic_home_selected')))

        // --- Tab 2: 控制 ---
        TabContent() {
          ControlPage()
        }
        .tabBar(this.TabBuilder('设备', 1, $r('app.media.ic_device_normal'), $r('app.media.ic_device_selected')))

        // --- Tab 3: AI ---
        TabContent() {
          ChatPage()
        }
        .tabBar(this.TabBuilder('AI助手', 2, $r('app.media.ic_chat_normal'), $r('app.media.ic_chat_selected')))
      }
      .scrollable(true)
      .onChange((index: number) => {
        this.currentIndex = index
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F5F5')
  }

  // 升级版的 TabBuilder：支持传入图片资源
  @Builder TabBuilder(title: string, targetIndex: number, normalIcon: Resource, selectedIcon: Resource) {
    Column() {
      // ⚠️ 底部导航图标
      Image(this.currentIndex === targetIndex ? selectedIcon : normalIcon)
        .width(24)
        .height(24)
        .margin({ bottom: 4 })
      // 如果你的图片是 svg 格式，可以直接用 fillColor 改变颜色，如果是 png 则需要准备两张图
      //  .fillColor(this.currentIndex === targetIndex ? '#4A90E2' : '#999999')

      Text(title)
        .fontColor(this.currentIndex === targetIndex ? '#4A90E2' : '#999999')
        .fontSize(10)
        .fontWeight(this.currentIndex === targetIndex ? FontWeight.Medium : FontWeight.Normal)
    }
    .width('100%')
    .height(60)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(Color.White)
    .onClick(() => {
      this.currentIndex = targetIndex
      this.controller.changeIndex(targetIndex)
    })
  }
}