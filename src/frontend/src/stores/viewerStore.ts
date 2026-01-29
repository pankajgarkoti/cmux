import { create } from 'zustand';

export interface ViewerFile {
  name: string;
  path: string;
  type: 'file' | 'directory';
}

interface ViewerState {
  selectedFile: ViewerFile | null;
  setSelectedFile: (file: ViewerFile | null) => void;
  clearSelectedFile: () => void;
}

export const useViewerStore = create<ViewerState>()((set) => ({
  selectedFile: null,
  setSelectedFile: (file) => set({ selectedFile: file }),
  clearSelectedFile: () => set({ selectedFile: null }),
}));
