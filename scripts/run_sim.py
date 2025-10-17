
from sankofa_sim.sim import run_economy_sim, SimConfig
import json, argparse

parser = argparse.ArgumentParser()
parser.add_argument("--days", type=int, default=20)
parser.add_argument("--tier", type=int, default=1)
parser.add_argument("--seed", type=lambda x:int(x,0), default=0xA2B94D10)
args = parser.parse_args()

cfg = SimConfig(campaign_seed=args.seed, days=args.days, realm_tier=args.tier)
result = run_economy_sim(cfg)

print(json.dumps(result, indent=2))
