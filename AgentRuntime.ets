import { AgentService } from './AgentService';
import { RemoteAIService } from './AIService';
import { TaskToolExecutor } from './TaskToolExecutor';
import { TaskDraftService } from './TaskDraftService';

export class AgentRuntime {
  private static instance: AgentService | null = null;
  static get(): AgentService {
    if (AgentRuntime.instance === null) {
      AgentRuntime.instance = new AgentService(new RemoteAIService(), new TaskToolExecutor(), TaskDraftService.getInstance());
    }
    return AgentRuntime.instance;
  }
}
