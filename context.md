# Cachy — Knowledge Graph Subsystem Specification

The **Knowledge Graph** is an interactive, emergent network visualization of the user's library inspired by Obsidian's graph view. Rather than serving as a static mind map, it is a living, force-directed particle simulation that calculates spatial layouts dynamically on the client while relying on the server for semantic topology and community detection.

---

## 1. Core Architectural Paradigm

```
Server (backend/app/api/graph.py)          Client (app/lib/ui/features/graph/)
┌─────────────────────────────────────┐    ┌──────────────────────────────────────┐
│ Semantic Topology & Edge Construction│    │ Live Force-Directed Physics Sim      │
│ Label Propagation Clustering (LP)   │───▶│ 60fps Ticker × 4 Configurable Forces │
│ Data Fingerprint Caching            │    │ Ego-Centric Local Graph (BFS)        │
│ NO Coordinate Calculation           │    │ Canvas LOD & Multi-Entity Rendering  │
└─────────────────────────────────────┘    └──────────────────────────────────────┘
```

1. **Separation of Concerns**: The backend computes **relational meaning** (similarity scoring, top-K filtering, community assignment). The Flutter client computes **spatial positioning** via real-time Newtonian physics.
2. **Emergent Clustering**: Semantic clusters form organically. Cards sharing high embedding similarity pull together via spring forces, while unrelated topic groups drift apart due to global repulsion.
3. **Multi-Entity Integration**: The graph unifies step-by-step knowledge cards (`node_type = 'card'`) and saved catalog media items (`node_type = 'catalog'`) into a single interconnected web.

---

## 2. Backend Topology & Caching Engine

Mounted under `GET /graph` (`backend/app/api/graph.py`).

### 2.1 Node Construction
- **Card Nodes**: Built from `CardRow` records where `state == READY`. Label is derived from `one_liner` or `caption` (capped at 80 chars).
- **Catalog Nodes**: Built from `ArtifactRow` records where `saved == True`.

### 2.2 Edge Construction & Scoring
Edge weights $w \in (0, 1]$ represent connection strength between node pairs:
1. **Card ↔ Card Similarity**:
   $$w_{\text{pair}} = \text{Cosine}(\vec{a}, \vec{b}) + \min\left(|\text{Tags}_a \cap \text{Tags}_b| \times 0.05,\; 0.15\right)$$
   - *Hairball Prevention*: For each card, candidate edges are thresholded ($\ge 0.55$), sorted by weight, and capped at `top_k` (default 4). An edge survives if it falls within either endpoint's top-K neighborhood.
2. **Catalog ↔ Card References**: Hard links derived directly from `ArtifactRow.source_card_ids` are assigned weight $w = 1.0$.

### 2.3 Edge Taxonomy (`kind`)
- `"semantic"`: Card pair with active embedding cosine similarity $> 0.1$.
- `"tag"`: Card pair connected purely via overlapping auto-tags.
- `"reference"`: Hard link connecting a catalog artifact to its source card.

### 2.4 Community Detection (Label Propagation)
Runs server-side in pure Python (`_label_propagation`):
- Every node initializes with a unique cluster ID. Over up to 30 iterations, nodes iteratively adopt the label representing the highest summed edge weight among their neighbors.
- **Auto-Labeling**: Clusters are labeled based on the predominant `content_type` (e.g., `recipe` $\rightarrow$ *"Recipes"*, `workout` $\rightarrow$ *"Fitness"*).

### 2.5 Fingerprint Caching (`_GraphCache`)
- To prevent $O(n^2)$ recomputation on every screen load, the graph response is cached in memory.
- **Cache Fingerprint**: MD5 hash of `card_count : max(card_updated_at) : artifact_count : max(artifact_updated_at)`.
- **Invalidation**: Card or catalog mutation endpoints (`create`, `patch`, `delete`, `save`) explicitly invoke `invalidate_graph_cache()`.

---

## 3. Client Data Models (`GraphData`)

Defined in `app/lib/domain/models/graph.dart`:
```dart
class GraphNode {
  final String id;
  final String label;
  final String nodeType;      // "card" | "catalog"
  final String contentType;   // e.g., "recipe", "book"
  final String? thumbnail;
  final List<String> tags;
  final int degree;           // Total connected edges
  final int clusterId;        // Community ID (-1 if isolated)
}

class GraphEdge {
  final String source;
  final String target;
  final double weight;
  final String kind;          // "semantic" | "reference" | "tag"
}

class GraphCluster {
  final int id;
  final String label;
  final int count;
}
```

---

## 4. Client Physics Simulation Engine

Implemented in `app/lib/ui/features/graph/views/graph_screen.dart` using a `SingleTickerProviderStateMixin` driving a 60fps frame loop (`_step`).

### 4.1 The 4-Force Mechanical Model
Configured via `_PhysicsConfig`:

| Force | Mathematical Law | Effect & Slider Bounds |
|---|---|---|
| **Repulsion** | Coulomb's Law:<br>$\vec{F} = \text{repelForce} \times \frac{k^2}{d^2} \hat{r}$ | Pushes every particle away from all others, preventing node pileups.<br>*Slider: 0.0 to 3.0* |
| **Spring (Link)** | Hooke's Law:<br>$\vec{F} = \text{linkForce} \times \left(\frac{d - k}{d}\right)(0.4 + w) \hat{r}$ | Pulls connected nodes toward rest length $k$. Stronger weights compress springs.<br>*Slider: 0.0 to 3.0* |
| **Center Gravity** | Gravitational Pull:<br>$\vec{F} = -\text{centerForce} \times \vec{p}$ | Gently pulls all nodes toward $(0,0)$ so disconnected islands don't drift away.<br>*Slider: 0.0 to 1.0* |
| **Link Distance** | Rest Rest Length ($k$) | Ideal spacing in virtual pixels.<br>*Slider: 30px to 200px* |

### 4.2 Thermodynamics & Drag (Rubber-Band Effect)
- **Cooling Schedule**: Simulation initializes at temperature $T = 90$. Each frame, $T_{t+1} = \max(0.4,\; T_t \times 0.96)$. Node displacement magnitude per step is clamped to $\le T$. Simulation sleeps when $T < 0.5$.
- **Momentum Damping**: Velocity $\vec{v}_{t+1} = (\vec{F} + \vec{v}_t \times 0.85) \times 0.5$, ensuring smooth kinetic deceleration.
- **Interactive Reheating**: Dragging any node locks its position to the touch coordinate while reheating global temperature to $T \ge 8.0$ (or $4.0$ during drag updates). Connected neighbors dynamically stretch and pull in real time around the dragged anchor.

---

## 5. UI Layout, Filtering & Canvas Rendering

### 5.1 Modes & Navigation
- **Global Graph**: Renders the complete library topology.
- **Local Graph Mode**: Ego-centric view triggered via the preview sheet's **Focus** button. Executes a Breadth-First Search (BFS) around `_localRoot` up to `_localDepth` (1 to 3 hops). A floating header banner allows exiting back to global view.
- **Settings Drawer**: Gear button opens a bottom sheet with interactive force sliders and local graph controls.

### 5.2 Multi-Entity Canvas Rendering (`_GraphPainter`)
Executed inside `CustomPainter`:
- **Node Shapes**:
  - `card`: Rendered as solid filled **circles** colored by `ContentAccent`.
  - `catalog`: Rendered as **rounded squares** (`RRect`) colored via a typed media palette.
- **Edge Styling**:
  - `semantic`: Solid line.
  - `reference`: Dashed line (`6px` dash, `4px` gap), increased thickness.
  - `tag`: Dotted line (`2px` dash, `4px` gap).
- **Selection & Cluster Dimming**: Selecting a cluster chip or node fades unrelated non-neighbor entities to `20%` opacity while drawing an outer halo around active items.
- **Level of Detail (LOD)**:
  - Zoom $< 0.65$: Text labels suppressed for canvas rendering fluidity.
  - Zoom $> 0.80$: Catalog nodes display a high-contrast media icon badge (book, film, headphones, etc.).
