// entry/src/main/ets/utils/GlobalConfig.ets

// export class GlobalConfig {
//   // 这里的 IP 会被 Python 脚本自动覆盖，保持这个格式即可
//   public static readonly SERVER_IP: string = '127.0.0.1';
//   public static readonly SERVER_PORT: string = '5000';
//
//   public static getBaseUrl(): string {
//     return `http://${GlobalConfig.SERVER_IP}:${GlobalConfig.SERVER_PORT}`;
//   }
// }
export class GlobalConfig {
  public static getBaseUrl(): string {
    // 👇 换成网络组同学电脑的真实局域网 IP 和端口
    return 'http://192.168.3.82:5000';
  }
}
