# Sample Project: Fibonacci Sequence Analysis

**Project Title**: Fibonacci Sequence Mathematical Properties

**Problem Statement**: 
Investigate the mathematical properties of the Fibonacci sequence, 
including its relationship to the golden ratio, matrix representation,
and applications in nature. Implement efficient computation methods
and verify known identities.

**Background/Context**:
The Fibonacci sequence F(n) = F(n-1) + F(n-2) with F(0)=0, F(1)=1 appears
in many mathematical contexts. Key properties include:
- F(n) ≈ φ^n / √5 where φ = (1+√5)/2 (golden ratio)
- Cassini's identity: F(n-1) * F(n+1) - F(n)^2 = (-1)^n
- Matrix representation for O(log n) computation

**Goals/Objectives**:
- Implement fast Fibonacci computation (matrix exponentiation)
- Verify golden ratio convergence empirically
- Test Cassini's identity for first 100 values
- Generate visualization of growth rate

**Scope**:
- Focus on computational verification
- Use Python with type hints
- Include comprehensive test suite

**Success Criteria**:
- [x] Fast Fibonacci function (matrix method) implemented
- [x] Golden ratio convergence verified for n=1 to 100
- [x] Cassini's identity tested for n=1..100 (all pass)
- [x] Growth rate analysis complete
- [ ] Visualization generated (optional)

**Priority**: Medium

**Notes**: 
This is a sample project demonstrating the workflow.
The team should focus on computational aspects rather than proofs.