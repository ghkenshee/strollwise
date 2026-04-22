# Use Cases Per Actor
## Local User:
- UC1 — Select User Type (Local)
- UC2 — View Map
- UC3 — Submit Pin
- UC5 — View Zone Details
- UC8 — Filter Zones by Type
## International User:
- UC1 — Select User Type (International)
- UC2 — View Zone Map
- UC3 — Submit Pin
- UC5 — View Zone Details
- UC8 — Filter Zones by Type
## System:
- UC9  — Convert GPS to H3 Zone ID (on device)
- UC10 — Discard Raw GPS Coordinates
- UC11 — *Check Against Restricted Zone Registry*
- UC12 — Aggregate Pin Contributions
- UC13 — Apply Threshold Check
- UC14 — Assign Zone Lifecycle State (Unthreshold/Emerging/Defined)
- UC15 — Assign Zone Color (Yellow/Blue/Green)
- UC16 — Publish Zone to Map
- UC17 — *Apply Zone Decay*

## Use Case Relationships
### Include relationships — these always happen together:
- UC3 (Submit Pin) includes UC9 (Convert GPS to H3)
- UC3 (Submit Pin) includes UC10 (Discard Raw GPS)
- *UC3 (Submit Pin) includes UC11 (Check Restricted Zone)*
- UC12 (Aggregate Pins) includes UC13 (Threshold Check)
- UC13 (Threshold Check) includes UC14 (Assign Lifecycle State)
- UC14 (Assign Lifecycle State) includes UC15 (Assign Color)
### Extend relationships — these happen conditionally:
- *UC6 (Restricted Zone Notice) extends UC3 (Submit Pin)*
  - → *Only if restricted zone detected*

- UC16 (Publish Zone) extends UC13 (Threshold Check)
  → Only if the threshold is met

- *UC17 (Zone Decay) extends UC14 (Assign Lifecycle State)*
  → *Only if contribution activity drops below the minimum*
`
