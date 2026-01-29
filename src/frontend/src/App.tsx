import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { Layout } from './components/layout/Layout';
import { AgentList } from './components/agents/AgentList';
import { CommandCenter } from './components/command/CommandCenter';
import { ActivityFeed } from './components/activity/ActivityFeed';
import { StatusBar } from './components/status/StatusBar';
import { useWebSocket } from './hooks/useWebSocket';

const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 5000,
      refetchInterval: 10000,
    },
  },
});

function Dashboard() {
  useWebSocket();

  return (
    <Layout>
      <div className="grid grid-cols-12 gap-4 h-full">
        {/* Left - Agents */}
        <div className="col-span-2 border-r overflow-hidden">
          <AgentList />
        </div>

        {/* Center - Command Center (main interaction) */}
        <div className="col-span-7 flex flex-col overflow-hidden">
          <CommandCenter />
        </div>

        {/* Right - Activity Stream */}
        <div className="col-span-3 border-l overflow-hidden">
          <ActivityFeed />
        </div>
      </div>

      <StatusBar />
    </Layout>
  );
}

export default function App() {
  return (
    <QueryClientProvider client={queryClient}>
      <Dashboard />
    </QueryClientProvider>
  );
}
