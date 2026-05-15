# Example diagrams (PlantUML)

```{.plantuml #fig:puml-class caption="PlantUML class diagram (example)"}
class Animal {
  +name: String
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

```{.plantuml #fig:puml-seq caption="PlantUML sequence diagram (example)"}
actor User as U
participant Web as W
participant AuthService as A
U -> W : submit credentials
W -> A : verify(user, pass)
A --> W : token
W --> U : set cookie
```

```{.plantuml #fig:puml-comp caption="PlantUML component diagram (example)"}
package "Frontend" {
  [Browser]
}
package "Backend" {
  [API Gateway] --> [Auth Service]
  [API Gateway] --> [Order Service]
  [Order Service] --> [Database]
}
[Browser] --> [API Gateway] : HTTPS
```
