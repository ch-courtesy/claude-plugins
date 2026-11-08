"""Minimal CMA-ES (Hansen's standard (mu/mu_w, lambda) update), numpy only."""
import numpy as np


class CMAES:
    def __init__(self, x0, sigma, popsize=None, seed=0):
        n = self.n = len(x0)
        self.mean = np.asarray(x0, float).copy()
        self.sigma = sigma
        self.lam = popsize or 4 + int(3 * np.log(n))
        self.mu = self.lam // 2
        w = np.log(self.mu + 0.5) - np.log(np.arange(1, self.mu + 1))
        self.w = w / w.sum()
        self.mueff = 1 / np.sum(self.w ** 2)
        self.cc = (4 + self.mueff / n) / (n + 4 + 2 * self.mueff / n)
        self.cs = (self.mueff + 2) / (n + self.mueff + 5)
        self.c1 = 2 / ((n + 1.3) ** 2 + self.mueff)
        self.cmu = min(1 - self.c1,
                       2 * (self.mueff - 2 + 1 / self.mueff) / ((n + 2) ** 2 + self.mueff))
        self.damps = 1 + 2 * max(0, np.sqrt((self.mueff - 1) / (n + 1)) - 1) + self.cs
        self.chiN = np.sqrt(n) * (1 - 1 / (4 * n) + 1 / (21 * n * n))
        self.pc, self.ps = np.zeros(n), np.zeros(n)
        self.B, self.D, self.C = np.eye(n), np.ones(n), np.eye(n)
        self.rng = np.random.default_rng(seed)
        self.gen = 0

    def ask(self):
        z = self.rng.standard_normal((self.lam, self.n))
        self._y = (z * self.D) @ self.B.T
        return self.mean + self.sigma * self._y

    def tell(self, fitness):
        order = np.argsort(fitness)
        y = self._y[order[: self.mu]]
        yw = self.w @ y
        self.mean = self.mean + self.sigma * yw
        inv_sqrt = self.B @ np.diag(1 / self.D) @ self.B.T
        self.ps = (1 - self.cs) * self.ps + np.sqrt(self.cs * (2 - self.cs) * self.mueff) * inv_sqrt @ yw
        hsig = (np.linalg.norm(self.ps) / np.sqrt(1 - (1 - self.cs) ** (2 * (self.gen + 1)))
                / self.chiN) < 1.4 + 2 / (self.n + 1)
        self.pc = (1 - self.cc) * self.pc + hsig * np.sqrt(self.cc * (2 - self.cc) * self.mueff) * yw
        rank_mu = (y.T * self.w) @ y
        self.C = ((1 - self.c1 - self.cmu) * self.C
                  + self.c1 * (np.outer(self.pc, self.pc)
                               + (1 - hsig) * self.cc * (2 - self.cc) * self.C)
                  + self.cmu * rank_mu)
        self.sigma *= np.exp((self.cs / self.damps) * (np.linalg.norm(self.ps) / self.chiN - 1))
        self.C = (self.C + self.C.T) / 2
        ev, self.B = np.linalg.eigh(self.C)
        self.D = np.sqrt(np.maximum(ev, 1e-20))
        self.gen += 1
