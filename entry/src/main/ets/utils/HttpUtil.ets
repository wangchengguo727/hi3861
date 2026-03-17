import http from '@ohos.net.http';

export class HttpUtil {
  // 单例模式
  private static instance: HttpUtil;

  public static getInstance(): HttpUtil {
    if (!HttpUtil.instance) {
      HttpUtil.instance = new HttpUtil();
    }
    return HttpUtil.instance;
  }

  /**
   * 发送 GET 请求 (用于查询数据)
   * @param url 请求地址
   * @param callback 成功回调
   */
  public get(url: string, callback: (result: string) => void) {
    let httpRequest = http.createHttp();

    httpRequest.request(
      url,
      {
        method: http.RequestMethod.GET,
        header: {
          'Content-Type': 'application/json'
        },
        readTimeout: 5000,
        connectTimeout: 5000
      },
      (err, data) => {
        if (!err && data.responseCode === 200) {
          // 处理返回结果
          if (data.result) {
            callback(data.result.toString());
          }
        } else {
          console.error('[HTTP] GET失败: ' + JSON.stringify(err));
        }
        httpRequest.destroy(); // 销毁请求
      }
    );
  }

  /**
   * 发送 POST 请求
   * @param url 请求地址
   * @param body 发送的数据 (Object 类型，ArkTS 不允许使用 any)
   * @param callback 成功回调
   */
  public post(url: string, body: Object, callback: (result: string) => void) {
    let httpRequest = http.createHttp();

    httpRequest.request(
      url,
      {
        method: http.RequestMethod.POST,
        header: {
          'Content-Type': 'application/json'
        },
        // 这里 JSON.stringify 支持传入 Object
        extraData: JSON.stringify(body),
        readTimeout: 5000,
        connectTimeout: 5000
      },
      (err, data) => {
        if (!err && data.responseCode === 200) {
          if (data.result) {
            callback(data.result.toString());
          }
        } else {
          console.error('[HTTP] POST失败: ' + JSON.stringify(err));
        }
        httpRequest.destroy();
      }
    );
  }
}

export default HttpUtil.getInstance();