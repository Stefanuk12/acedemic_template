# Example diagrams (Mermaid)

```{.mermaid #fig:mermaid-class caption="Mermaid class diagram (example)"}
classDiagram
    class Animal {
      +String name
      +makeSound()
    }
    class Dog {
      +bark()
    }
    class Cat {
      +meow()
    }
    Animal <|-- Dog
    Animal <|-- Cat
```

```{.mermaid #fig:mermaid-seq caption="Mermaid sequence diagram (example)"}
sequenceDiagram
    participant U as User
    participant W as Web
    participant A as AuthService
    U->>W: submit credentials
    W->>A: verify(user, pass)
    A-->>W: token
    W-->>U: set cookie
```
