import { create } from 'zustand';
import { persist } from 'zustand/middleware';

interface LayoutState {
  leftPanelSize: number;
  rightPanelSize: number;
  setLeftPanelSize: (size: number) => void;
  setRightPanelSize: (size: number) => void;
}

export const useLayoutStore = create<LayoutState>()(
  persist(
    (set) => ({
      leftPanelSize: 15,
      rightPanelSize: 25,
      setLeftPanelSize: (size) => set({ leftPanelSize: size }),
      setRightPanelSize: (size) => set({ rightPanelSize: size }),
    }),
    {
      name: 'cmux-layout',
    }
  )
);
