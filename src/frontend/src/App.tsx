import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { Layout } from './components/layout/Layout';
import { AgentList } from './components/agents/AgentList';
import { ActivityFeed } from './components/activity/ActivityFeed';
import { MessageInput } from './components/messages/MessageInput';
import { MessageList } from './components/messages/MessageList';
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
        {/* Agent List - Left Sidebar */}
        <div className="col-span-3 border-r">
          <AgentList />
        </div>

        {/* Main Content - Activity Feed */}
        <div className="col-span-6 flex flex-col">
          <ActivityFeed />
          <MessageInput />
        </div>

        {/* Right Panel - Messages */}
        <div className="col-span-3 border-l">
          <MessageList />
        </div>
      </div>

      {/* Status Bar */}
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
