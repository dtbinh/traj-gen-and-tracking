TODO List:

SL TODO:

- Load DMPs using weights only
- Include safety methods in trajectory task
- Check the different functions in SL for table tennis [Yanlong's and others]
- How to integrate filtering with ILC?
- How to filter correctly in SL (test filter fncs on MATLAB)
- Why does previous SL version show different results? [bringing back to q0]
- Fix indexing issue on uffs vs. states
- Test basic ILC (with/without LQR, and filtering)

REAL ROBOT TODO:

- Test LQR and different feedback (LQG?) w/o learning
- Test different DMPs, with different taus and velocities w/o learning
- Which parameters to use?
- Incorporate extending horizon as worst case for experiments

General TODO (i.e. MATLAB):

- Make MATLAB experiments for generalization: regression, convex hull learning. 
  Are the weights necessary for generalization? 
- Optimize DMPs with minimum jerk criterion
- Test LQG on MATLAB 
- Does aILC work on robot classes? EM algorithm as an extension ?
- Correct paper with SL results, change methodology
- Implement REPS, PI2 algorithms on MATLAB

READING TODO:

- Read robotics book up to control chapters
- Review filtering theory
- Read maximum principle chapter
- Read policy search review
- Read some more ILC papers
- Read the Barrett WAM inertial specifications

FUTURE TODO:

- Total Least Squares implementation for ILC?
- Check DDP and explore fully the connection with ILC (and regression?)
- Recursive pseudoinverse feasible? Connection to IDM?
- Prove ILC convergence : keep Fk bounded and show that the cost fnc is convex
- Try IDM as fb in MATLAB
- Articulate inverse dynamics in MATLAB does not match to SL! [in SL it is as good as NE]
implement the test function in MATLAB that checks for differences
- How to take inverse in end-goal learning in Mayer form
- Symplectic Euler causes problems for convergence in RR
- Why does the width (h) of the basis functions matter?
- Why are two tracking LQRs not exactly the same (at the end)? 
  [maybe R dependence is not correct, index difference?]
- Effects of error coupling on DMPs?
- Why does ILC learning with feedback not improve?
- Fast ways to construct, parameterize LQR matrix K or ILC matrix F online?
- Investigate LQR differences for different trajectories.
- Variational Bayes for estimating noise on positions and velocities?