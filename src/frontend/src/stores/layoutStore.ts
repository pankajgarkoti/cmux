import { create } from 'zustand';
import { persist } from 'zustand/middleware';

interface LayoutState {
  leftPanelSize: number;
  rightPanelSize: number;
  rightPanelCollapsed: boolean;
  savedRightPanelSize: number;
  setLeftPanelSize: (size: number) => void;
  setRightPanelSize: (size: number) => void;
  toggleRightPanel: () => void;
  collapseRightPanel: () => void;
  expandRightPanel: () => void;
}

export const useLayoutStore = create<LayoutState>()(
  persist(
    (set, get) => ({
      leftPanelSize: 15,
      rightPanelSize: 25,
      rightPanelCollapsed: false,
      savedRightPanelSize: 25,
      setLeftPanelSize: (size) => set({ leftPanelSize: size }),
      setRightPanelSize: (size) => {
        if (size > 0) {
          set({ rightPanelSize: size, savedRightPanelSize: size, rightPanelCollapsed: false });
        } else {
          set({ rightPanelSize: 0, rightPanelCollapsed: true });
        }
      },
      toggleRightPanel: () => {
        const { rightPanelCollapsed, savedRightPanelSize } = get();
        if (rightPanelCollapsed) {
          set({ rightPanelSize: savedRightPanelSize, rightPanelCollapsed: false });
        } else {
          set({ rightPanelSize: 0, rightPanelCollapsed: true });
        }
      },
      collapseRightPanel: () => {
        const { rightPanelSize } = get();
        if (rightPanelSize > 0) {
          set({ savedRightPanelSize: rightPanelSize, rightPanelSize: 0, rightPanelCollapsed: true });
        }
      },
      expandRightPanel: () => {
        const { savedRightPanelSize } = get();
        set({ rightPanelSize: savedRightPanelSize, rightPanelCollapsed: false });
      },
    }),
    {
      name: 'cmux-layout',
    }
  )
);
