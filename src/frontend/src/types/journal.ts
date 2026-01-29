export interface JournalDayResponse {
  date: string;
  content: string;
  artifacts: string[];
}

export interface JournalDatesResponse {
  dates: string[];
}

export interface JournalSearchResult {
  date: string;
  title: string;
  snippet: string;
  line_number: number;
}

export interface JournalSearchResponse {
  query: string;
  results: JournalSearchResult[];
  total: number;
}

export interface JournalEntryCreate {
  title: string;
  content: string;
}
