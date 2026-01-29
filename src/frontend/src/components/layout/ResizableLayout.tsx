import {
  ResizablePanelGroup,
  ResizablePanel,
  ResizableHandle,
} from '@/components/ui/resizable';
import { useLayoutStore } from '@/stores/layoutStore';

interface ResizableLayoutProps {
  left: React.ReactNode;
  center: React.ReactNode;
  right: React.ReactNode;
}

export function ResizableLayout({ left, center, right }: ResizableLayoutProps) {
  const { leftPanelSize, rightPanelSize, setLeftPanelSize, setRightPanelSize } = useLayoutStore();

  return (
    <ResizablePanelGroup
      orientation="horizontal"
      className="h-full"
      onLayoutChanged={(layout) => {
        const leftSize = layout['left-panel'];
        const rightSize = layout['right-panel'];
        if (leftSize !== undefined && leftSize !== leftPanelSize) {
          setLeftPanelSize(leftSize);
        }
        if (rightSize !== undefined && rightSize !== rightPanelSize) {
          setRightPanelSize(rightSize);
        }
      }}
    >
      {/* Left Panel - Explorer */}
      <ResizablePanel
        id="left-panel"
        defaultSize={`${leftPanelSize}%`}
        minSize="10%"
        maxSize="25%"
        className="bg-sidebar-background"
        style={{ overflow: 'visible' }}
      >
        {left}
      </ResizablePanel>

      <ResizableHandle withHandle />

      {/* Center Panel - Command Center */}
      <ResizablePanel
        id="center-panel"
        defaultSize={`${100 - leftPanelSize - rightPanelSize}%`}
        minSize="30%"
      >
        {center}
      </ResizablePanel>

      <ResizableHandle withHandle />

      {/* Right Panel - Activity Feed */}
      <ResizablePanel
        id="right-panel"
        defaultSize={`${rightPanelSize}%`}
        minSize="15%"
        maxSize="40%"
        className="bg-sidebar-background"
      >
        {right}
      </ResizablePanel>
    </ResizablePanelGroup>
  );
}
