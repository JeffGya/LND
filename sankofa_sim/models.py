
from dataclasses import dataclass, field
from typing import List, Dict

@dataclass
class Hero:
    name: str
    courage: int = 6
    wisdom: int = 6
    faith: int = 6
    morale: float = 80.0
    fear: float = 0.0

@dataclass
class Sanctum:
    faith: float = 60.0
    harmony: float = 55.0
    favor: float = 20.0
    ase: float = 200.0
    ekwan: float = 100.0

@dataclass
class RealmState:
    tier: int = 1
    corruption: float = 25.0
