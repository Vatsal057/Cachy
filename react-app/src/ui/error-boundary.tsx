import { Component } from 'react';
import type { ReactNode } from 'react';

interface Props {
  children: ReactNode;
}

interface State {
  error: Error | null;
}

/**
 * Catches render crashes and shows the error instead of a blank screen.
 * Temporary diagnostic — remove once the crash is fixed.
 */
export class ErrorBoundary extends Component<Props, State> {
  state: State = { error: null };

  static getDerivedStateFromError(error: Error): State {
    return { error };
  }

  componentDidCatch(error: Error, info: { componentStack: string }) {
    console.error('ErrorBoundary caught:', error, info.componentStack);
  }

  render() {
    if (this.state.error) {
      return (
        <div style={{ padding: 24, color: '#fff', background: '#181818', minHeight: '100vh' }}>
          <h2 style={{ color: '#ff6b6b' }}>Something crashed</h2>
          <pre style={{ whiteSpace: 'pre-wrap', fontSize: 13 }}>
            {String(this.state.error.message)}
          </pre>
          <pre style={{ whiteSpace: 'pre-wrap', fontSize: 11, opacity: 0.7 }}>
            {String(this.state.error.stack)}
          </pre>
          <button
            onClick={() => window.location.reload()}
            style={{ marginTop: 16, padding: '10px 20px' }}
          >
            Reload
          </button>
        </div>
      );
    }
    return this.props.children;
  }
}
