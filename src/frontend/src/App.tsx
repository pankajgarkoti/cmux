import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { Layout } from './components/layout/Layout';
import { ResizableLayout } from './components/layout/ResizableLayout';
import { Explorer } from './components/explorer/Explorer';
import { ChatPanel } from './components/chat/ChatPanel';
import { ActivityTimeline } from './components/activity/ActivityTimeline';
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
      <ResizableLayout
        left={<Explorer />}
        center={<ChatPanel />}
        right={<ActivityTimeline />}
      />
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
