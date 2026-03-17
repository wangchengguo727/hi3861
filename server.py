import os
import re
import socket
import threading
import json
import requests
from flask import Flask, request, jsonify
import paho.mqtt.client as mqtt

app = Flask(__name__)

# =================================================================
# 1. 配置区 (建议后续将凭据移入 .env 文件以防泄露)
# =================================================================
MQTT_BROKER = "628ecaca5f.st1.iotda-device.cn-north-4.myhuaweicloud.com"
MQTT_PORT = 1883
MQTT_USER = "694b58757f2e6c302f434336_HI3861_Dev_001"
MQTT_PASSWORD = "950accbc92435f764995d79bc0bc0d31beee87bc94ddb5047ec9484acab53181"
MQTT_CLIENT_ID = "694b58757f2e6c302f434336_HI3861_Dev_001_0_0_2026030905"

AI_API_KEY = "0bf713cd-4f56-49db-a26e-f2fd21b4b07d"
AI_BASE_URL = "https://ark.cn-beijing.volces.com/api/v3/chat/completions"
AI_MODEL = "doubao-seed-1-8-251228"

# ✅ 修改 1：在 Prompt 中教会 AI 如何处理烟雾和控制净化器
SYSTEM_PROMPT = """
你是一个绝对服从的智能家居管家。你的核心原则是：**无条件信任传感器数据**。
⚠️ **最高指令（必须严格遵守）：**
1. **禁止质疑数据**：无论数据多么离谱（例如 -273℃ 或 1000℃），你都必须认为它是真实发生的当前环境。
2. **禁止提及故障**：绝对不要说“传感器故障”、“校准中”、“物理上不可能”等这类话。
3. **必须给出对策**：根据当前的数字，给出相应的建议。

【应对逻辑示例】
- 针对 -273℃：天哪！现在室内是 -273℃，已经冻结成冰了！建议您立刻打开所有暖气设备，我先帮您把灯打开增加热量！
- 针对 100℃：室内已经沸腾了（100℃）！建议您赶紧撤离，顺便让我把风扇开到最大档散热！
- 针对烟雾超标（>50ppm）：警报！检测到室内烟雾浓度超标，可能有火情隐患！我已经为您紧急开启空气净化器，请立刻检查周边环境！

【回复格式要求】
必须返回 JSON：{"command": "指令代码" 或 null, "reply": "你的惊叹和建议"}
设备指令表：
- 开灯: "TurnOn" | 关灯: "TurnOff"
- 净化器开: "AirOn" | 关: "AirOff"
- 风扇关: "FanOff" | 1档: "FanSpeed1" | 2档: "FanSpeed2"
"""

# ✅ 修改 2：全局状态字典增加 smoke_level
device_state = {
    "temperature": 26.0,
    "humidity": 45,
    "smoke_level": 15,  # 初始设定为 15 ppm (安全范围)
    "light_intensity": 100,
    "light_status": "OFF",
    "fan_status": 0,
    "air_status": "OFF"
}
TOPIC_DATA = "mysmart/data"
TOPIC_CMD = "mysmart/control"


# =================================================================
# 2. 自动化工具：动态 IP 注入 (ArkTS 配置文件热重载)
# =================================================================
def sync_ip_to_frontend():
    """获取本机物理网卡 IP 并正则覆写 GlobalConfig.ets"""
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(('8.8.8.8', 80))
        current_ip = s.getsockname()[0]
    except Exception:
        current_ip = "127.0.0.1"
    finally:
        s.close()

    print(f">>> [系统] 探测到本机局域网 IP: {current_ip}")
    base_dir = os.path.dirname(os.path.abspath(__file__))
    ets_config_path = os.path.join(base_dir, "entry", "src", "main", "ets", "utils", "GlobalConfig.ets")

    if not os.path.exists(ets_config_path):
        print(f"!!! [警告] 未找到 {ets_config_path}，请手动确认路径。")
        return current_ip

    with open(ets_config_path, 'r', encoding='utf-8') as f:
        content = f.read()

    new_content = re.sub(
        r"(SERVER_IP:\s*string\s*=\s*')[^']+'",
        rf"\g<1>{current_ip}'",
        content
    )

    with open(ets_config_path, 'w', encoding='utf-8') as f:
        f.write(new_content)

    print(f">>> [系统] 自动化挂载完成：已将 IP {current_ip} 注入 ArkTS 编译器")
    return current_ip


# =================================================================
# 3. 核心业务逻辑 (MQTT & Flask API)
# =================================================================
def on_connect(client, userdata, flags, rc):
    print(f">>> [MQTT] 连接状态: {'✅ 成功' if rc == 0 else '❌ 失败'}")
    if rc == 0: client.subscribe(TOPIC_DATA)


def on_message(client, userdata, msg):
    try:
        payload = msg.payload.decode()
        data = json.loads(payload)
        target = data.get('content', data)
        for k, v in target.items():
            if k in device_state: device_state[k] = v
    except Exception as e:
        print(f"[MQTT解析错误] {e}")


mqtt_client = mqtt.Client(client_id=MQTT_CLIENT_ID)
mqtt_client.username_pw_set(MQTT_USER, MQTT_PASSWORD)
mqtt_client.on_connect = on_connect
mqtt_client.on_message = on_message


def start_mqtt():
    try:
        mqtt_client.connect(MQTT_BROKER, MQTT_PORT, 60)
        mqtt_client.loop_forever()
    except Exception as e:
        print(f"[MQTT断开] {e}")


@app.route('/get_data', methods=['GET'])
def get_data():
    return jsonify({"result": device_state, "code": 200, "msg": "success"})


@app.route('/control', methods=['POST'])
def control():
    try:
        command = request.json.get('command')
        if not command:
            return jsonify({"result": "error", "msg": "无效指令"})

        print(f">>> [手动控制] 收到指令: {command}")

        # 乐观锁/预更新 UI 状态
        if command == 'TurnOn':
            device_state['light_status'] = 'ON'
        elif command == 'TurnOff':
            device_state['light_status'] = 'OFF'
        elif command == 'AirOn':
            device_state['air_status'] = 'ON'
        elif command == 'AirOff':
            device_state['air_status'] = 'OFF'
            # 👇 新增下面这三行风扇逻辑
        elif command == 'FanOff':
            device_state['fan_status'] = 0
        elif command == 'FanSpeed1':
            device_state['fan_status'] = 1
        elif command == 'FanSpeed2':
            device_state['fan_status'] = 2


        mqtt_client.publish(TOPIC_CMD, json.dumps({"command": command}))
        return jsonify({"result": "ok", "msg": "指令已发送"})
    except Exception as e:
        return jsonify({"result": "error", "msg": str(e)})


@app.route('/chat', methods=['POST'])
def chat():
    user_text = request.json.get('text', '')
    print(f"\n[用户说] {user_text}")

    # ✅ 修改 3：将实时烟雾数据挂载到 RAG 的提示词上下文中
    current_context = f"""
[实时环境监测数据]
- 室内温度: {device_state.get('temperature', '未知')}℃
- 室内湿度: {device_state.get('humidity', '未知')}%
- 烟雾浓度: {device_state.get('smoke_level', 15)} ppm
- 主灯状态: {'已开启' if device_state.get('light_status') == 'ON' else '已关闭'}
- 空气净化器: {'已开启' if device_state.get('air_status') == 'ON' else '已关闭'}
- 风扇状态: {device_state.get('fan_status', 0)}档
"""
    final_system_prompt = SYSTEM_PROMPT + "\n" + current_context

    try:
        headers = {"Authorization": f"Bearer {AI_API_KEY}", "Content-Type": "application/json"}
        payload = {
            "model": AI_MODEL,
            "messages": [
                {"role": "system", "content": final_system_prompt},
                {"role": "user", "content": user_text}
            ],
            "stream": False
        }

        print(">>> 呼叫火山引擎 RAG 节点...")
        resp = requests.post(AI_BASE_URL, headers=headers, json=payload, timeout=60)

        if resp.status_code != 200:
            print(f"!!! 火山引擎报错拦截: 状态码 {resp.status_code}, 详情: {resp.text}")
            return jsonify({"code": 500, "reply": "大语言模型网关超时"})

        ai_raw_content = resp.json()['choices'][0]['message']['content']
        clean_content = ai_raw_content.replace('```json', '').replace('```', '').strip()

        try:
            ai_json = json.loads(clean_content)
        except:
            ai_json = {"command": None, "reply": clean_content}

        reply_text = ai_json.get('reply', '格式化失败，降级输出。')
        command = ai_json.get('command')

        if command:
            print(f">>> [Agent 触发动作] 执行指令: {command}")
            if command == 'TurnOn':
                device_state['light_status'] = 'ON'
            elif command == 'TurnOff':
                device_state['light_status'] = 'OFF'
            elif command == 'AirOn':
                device_state['air_status'] = 'ON'
            elif command == 'AirOff':
                device_state['air_status'] = 'OFF'
            # 👇 就是这里！必须把风扇的记忆加上，AI 修改的才会生效
            elif command == 'FanOff':
                device_state['fan_status'] = 0
            elif command == 'FanSpeed1':
                device_state['fan_status'] = 1
            elif command == 'FanSpeed2':
                device_state['fan_status'] = 2

            mqtt_client.publish(TOPIC_CMD, json.dumps({"command": command}))

        return jsonify({"code": 200, "reply": reply_text})

    except Exception as e:
        print(f"大模型调用抛出异常: {e}")
        return jsonify({"code": 500, "reply": "AI Agent 离线。"})


if __name__ == '__main__':
    sync_ip_to_frontend()
    threading.Thread(target=start_mqtt, daemon=True).start()
    app.run(host='0.0.0.0', port=5000, debug=False, use_reloader=False)