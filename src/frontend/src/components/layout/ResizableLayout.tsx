import {
  ResizablePanelGroup,
  ResizablePanel,
  ResizableHandle,
} from '@/components/ui/resizable';
import { useLayoutStore } from '@/stores/layoutStore';
import { Button } from '@/components/ui/button';
import { PanelRightClose, PanelRightOpen } from 'lucide-react';

interface ResizableLayoutProps {
  left: React.ReactNode;
  center: React.ReactNode;
  right: React.ReactNode;
}

export function ResizableLayout({ left, center, right }: ResizableLayoutProps) {
  const {
    leftPanelSize,
    rightPanelSize,
    rightPanelCollapsed,
    setLeftPanelSize,
    setRightPanelSize,
    toggleRightPanel,
  } = useLayoutStore();

  return (
    <ResizablePanelGroup
      orientation="horizontal"
      className="h-full"
    >
      {/* Left Panel - Explorer */}
      <ResizablePanel
        id="left-panel"
        defaultSize={leftPanelSize}
        minSize={10}
        maxSize={25}
        className="bg-sidebar-background"
        style={{ overflow: 'visible' }}
        onResize={(size) => {
          const numSize = size.asPercentage;
          if (numSize !== leftPanelSize) {
            setLeftPanelSize(numSize);
          }
        }}
      >
        {left}
      </ResizablePanel>

      <ResizableHandle withHandle />

      {/* Center Panel - Command Center / File Viewer */}
      <ResizablePanel
        id="center-panel"
        defaultSize={100 - leftPanelSize - (rightPanelCollapsed ? 0 : rightPanelSize)}
        minSize={30}
      >
        <div className="relative h-full">
          {center}
          {/* Activity panel toggle button */}
          <Button
            variant="ghost"
            size="icon"
            className="absolute top-3 right-3 h-7 w-7 z-10"
            onClick={toggleRightPanel}
            title={rightPanelCollapsed ? 'Show activity panel' : 'Hide activity panel'}
          >
            {rightPanelCollapsed ? (
              <PanelRightOpen className="h-4 w-4" />
            ) : (
              <PanelRightClose className="h-4 w-4" />
            )}
          </Button>
        </div>
      </ResizablePanel>

      <ResizableHandle withHandle />

      {/* Right Panel - Activity Feed */}
      <ResizablePanel
        id="right-panel"
        defaultSize={rightPanelCollapsed ? 0 : rightPanelSize}
        minSize={0}
        maxSize={40}
        collapsible
        collapsedSize={0}
        className="bg-sidebar-background"
        onResize={(size) => {
          const numSize = size.asPercentage;
          if (numSize !== rightPanelSize) {
            setRightPanelSize(numSize);
          }
        }}
      >
        {right}
      </ResizablePanel>
    </ResizablePanelGroup>
  );
}
