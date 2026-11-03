/** No provider API key belongs in the application. For emulator: hdc rport tcp:3000 tcp:3000. */
export class AgentConfig {
  static readonly seedDemoOnEmpty: boolean = false;
  static gatewayUrl: string = 'http://127.0.0.1:3000';
  // Optional short-lived gateway access credential, entered at runtime, never persisted.
  static gatewayToken: string = '';

  static configure(url: string, token: string): void {
    const normalized = url.trim().replace(/\/$/, '');
    if (!/^https:\/\/[a-zA-Z0-9.-]+(?::\d+)?$/.test(normalized) &&
      !/^http:\/\/(127\.0\.0\.1|localhost)(?::\d+)?$/.test(normalized)) {
      throw new Error('网关地址应为 HTTPS，模拟器本机转发可使用 http://127.0.0.1:3000');
    }
    AgentConfig.gatewayUrl = normalized;
    AgentConfig.gatewayToken = token.trim();
  }
}
