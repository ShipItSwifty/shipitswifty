/**
 * @format
 */

import React from 'react';
import ReactTestRenderer from 'react-test-renderer';
import App from '../App';

describe('App', () => {
  it('renders without crashing', async () => {
    let renderer: ReactTestRenderer.ReactTestRenderer;
    await ReactTestRenderer.act(() => {
      renderer = ReactTestRenderer.create(<App />);
    });
    expect(renderer!).toBeTruthy();
  });

  it('renders a root element', async () => {
    let renderer: ReactTestRenderer.ReactTestRenderer;
    await ReactTestRenderer.act(() => {
      renderer = ReactTestRenderer.create(<App />);
    });
    const root = renderer!.toJSON();
    expect(root).not.toBeNull();
  });

  it('renders a non-empty tree', async () => {
    let renderer: ReactTestRenderer.ReactTestRenderer;
    await ReactTestRenderer.act(() => {
      renderer = ReactTestRenderer.create(<App />);
    });
    const json = renderer!.toJSON();
    const tree = Array.isArray(json) ? json : [json];
    expect(tree.length).toBeGreaterThan(0);
  });

  it('renders a single root component', async () => {
    let renderer: ReactTestRenderer.ReactTestRenderer;
    await ReactTestRenderer.act(() => {
      renderer = ReactTestRenderer.create(<App />);
    });
    const instance = renderer!.root;
    expect(instance).toBeDefined();
    expect(instance.type).toBeDefined();
  });

  it('renders consistent output across two instances', async () => {
    let renderer1: ReactTestRenderer.ReactTestRenderer;
    let renderer2: ReactTestRenderer.ReactTestRenderer;
    await ReactTestRenderer.act(() => {
      renderer1 = ReactTestRenderer.create(<App />);
    });
    await ReactTestRenderer.act(() => {
      renderer2 = ReactTestRenderer.create(<App />);
    });
    expect(JSON.stringify(renderer1!.toJSON())).toBe(
      JSON.stringify(renderer2!.toJSON()),
    );
  });

  it('can be unmounted without errors', async () => {
    let renderer: ReactTestRenderer.ReactTestRenderer;
    await ReactTestRenderer.act(() => {
      renderer = ReactTestRenderer.create(<App />);
    });
    expect(() => {
      ReactTestRenderer.act(() => {
        renderer.unmount();
      });
    }).not.toThrow();
  });

  it('produces a JSON-serializable tree', async () => {
    let renderer: ReactTestRenderer.ReactTestRenderer;
    await ReactTestRenderer.act(() => {
      renderer = ReactTestRenderer.create(<App />);
    });
    expect(() => JSON.stringify(renderer!.toJSON())).not.toThrow();
  });
});
