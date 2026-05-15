# Example diagrams (Graphviz)

Graphviz is the venerable graph-rendering tool — node-and-edge graphs,
trees, and dependency diagrams. The optional `engine=` attribute picks
the layout algorithm (`dot`, `neato`, `fdp`, `sfdp`, `twopi`, `circo`).

```{.dot #fig:gv-deps caption="Graphviz dependency graph (example)"}
digraph dependencies {
    rankdir=LR;
    node [shape=box, style=filled, fillcolor="#e8f0f8"];

    Frontend -> API;
    API -> AuthService [label="validate"];
    API -> Database [label="query"];
    AuthService -> Database;
    AuthService -> Cache [label="session"];
    API -> Cache [label="rate-limit"];
}
```

```{.dot #fig:gv-cluster caption="Graphviz force-directed layout (example)" engine=neato}
graph cluster {
    node [shape=circle, style=filled, fillcolor="#cce0ff"];

    A -- B; A -- C; A -- D;
    B -- E; B -- F;
    C -- G; C -- H;
    D -- I;
    E -- F;
    G -- H;
}
```
