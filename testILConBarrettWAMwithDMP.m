%% ILC on BarrettWAM dynamics modifying DMPs now

%# store breakpoints
tmp = dbstatus;
save('tmp.mat','tmp')

%# clear all
close all
clear classes %# clears even more than clear all
clc

%# reload breakpoints
load('tmp.mat')
dbstop(tmp)

%# clean up
clear tmp
delete('tmp.mat')

% folder that stores all data
prefs_folder = '../robolab/barrett/prefs/';
% folder that stores all config files, link parameters, etc.
config_folder = '../robolab/barrett/config/';

%% Define constants and parameters

N_DOFS = 7;
% Simulation Values 
% system is continous
SIM.discrete = false;
% learn in cartesian space
SIM.cartesian = false;
% dimension of the x vector
SIM.dimx = 2*N_DOFS;
% dimension of the output y
SIM.dimy = 2*N_DOFS;
% dimension of the control input
SIM.dimu = N_DOFS;
% time step h 
SIM.h = 0.005; % 200 Hz recorded data
% noise and initial error
SIM.eps = 3e-10;
SIM.eps_d = 3e-10;
% integration method
SIM.int = 'Euler';
% reference trajectory in joint space?
SIM.jref = true;

% definitions
ZSFE  =  0.346;              %!< z height of SAA axis above ground
ZHR  =  0.505;              %!< length of upper arm until 4.5cm before elbow link
YEB  =  0.045;              %!< elbow y offset
ZEB  =  0.045;              %!< elbow z offset
YWR  = -0.045;              %!< elbow y offset (back to forewarm)
ZWR  =  0.045;              %!< elbow z offset (back to forearm)
ZWFE  =  0.255;              %!< forearm length (minus 4.5cm)

% link 0 is the base
link0.m = 0.0;
link0.mcm(1) = 0.0;
link0.mcm(2) = 0.0;
link0.mcm(3) = 0.0;
link0.inertia(1,1) = 0.0; 
link0.inertia(1,2) = 0.0; 
link0.inertia(1,3) = 0.0; 
link0.inertia(2,2) = 0.0;   
link0.inertia(2,3) = 0.0;  
link0.inertia(3,3) = 0.0;  

% End effector parameters
eff(1).m = 0.0;
eff(1).mcm(1) = 0.0;
eff(1).mcm(2) = 0.0;
eff(1).mcm(3) = 0.0;
eff(1).x(1)  = 0.0;
eff(1).x(2)  = 0.0;
eff(1).x(3)  = 0.06; 
eff(1).a(1)  = 0.0;
eff(1).a(2)  = 0.0;
eff(1).a(3)  = 0.0;

% External forces
for j = 1:3
    % I guess this is the external force to the base
    uex0.f(j) = 0.0;
    uex0.t(j) = 0.0;
    for i = 1:7
        uex(i).f(j) = 0.0;
        uex(i).t(j) = 0.0;
    end
end

% SFE joint
links(1).m = 0.00000; 
links(1).mcm(1) = -0.00000;
links(1).mcm(2) = 0.00000;
links(1).mcm(3) = -0.00000;  
links(1).inertia(1,1) = 0.00000; 
links(1).inertia(1,2) = -0.00000; 
links(1).inertia(1,3) = -0.00000; 
links(1).inertia(2,2) = 0.00000;   
links(1).inertia(2,3) = 0.00000;  
links(1).inertia(3,3) = 0.00000;  
% SAA joint
links(2).m = 0.00000;  
links(2).mcm(1) = 0.43430; 
links(2).mcm(2) = -0.00495;
links(2).mcm(3) = -0.00000;
links(2).inertia(1,1) = 0.24768;  
links(2).inertia(1,2) = 0.00364;
links(2).inertia(1,3) = 0.17270;  
links(2).inertia(2,2) = 0.53601; 
links(2).inertia(2,3) = -0.02929; 
links(2).inertia(3,3) =  0.12406;  
% HR joint    
links(3).m = 3.53923; 
links(3).mcm(1) = -0.00889;
links(3).mcm(2) = -0.02148;
links(3).mcm(3) = -1.70741;
links(3).inertia(1,1) = 0.82985;
links(3).inertia(1,2) = -0.01520;
links(3).inertia(1,3) = -0.00612;
links(3).inertia(2,2) = 0.86182;
links(3).inertia(2,3) = -0.00575;
links(3).inertia(3,3) = 0.00071;
% EB joint (elbow)
links(4).m = 1.03409;
links(4).mcm(1) = 0.14089;
links(4).mcm(2) = -0.05914;
links(4).mcm(3) = -0.00270;
links(4).inertia(1,1) = 0.01276;
links(4).inertia(1,2) = 0.00340;
links(4).inertia(1,3) = -0.00229;
links(4).inertia(2,2) = 0.02157;
links(4).inertia(2,3) = 0.00032;
links(4).inertia(3,3) = 0.03718;
% WR joint (wrist 1)
links(5).m = 2.28843;
links(5).mcm(1) = 0.00709;
links(5).mcm(2) = 0.00194; 
links(5).mcm(3) = 0.22347; 
links(5).inertia(1,1) = 0.02182;
links(5).inertia(1,2) = -0.00001;
links(5).inertia(1,3) = -0.00069;
links(5).inertia(2,2) = 0.02184;
links(5).inertia(2,3) = -0.00019;
links(5).inertia(3,3) = 0.00002;
% WFE joint (wrist 2)
links(6).m = 0.25655; 
links(6).mcm(1) = 0.03462; 
links(6).mcm(2) = -0.00415;  
links(6).mcm(3) = 0.00121; 
links(6).inertia(1,1) = 0.00167; 
links(6).inertia(1,2) = 0.00079; 
links(6).inertia(1,3) = -0.00009; 
links(6).inertia(2,2) = 0.00483; 
links(6).inertia(2,3) = -0.00084;
links(6).inertia(3,3) = 0.01101;
% WAA joint (wrist 3)
links(7).m = 0.63285; 
links(7).mcm(1) = -0.00157;  
links(7).mcm(2) = 0.00019;  
links(7).mcm(3) = 0.08286;  
links(7).inertia(1,1) = 0.01129; 
links(7).inertia(1,2) = -0.00006;
links(7).inertia(1,3) = -0.00006;  
links(7).inertia(2,2) = 0.01086; 
links(7).inertia(2,3) = 0.00001;  
links(7).inertia(3,3) = 0.00016;

% make sure inertia matrices are symmetric
for i = 1:7
    for j = 1:3
        for k = j:3
            links(i).inertia(k,j) = links(i).inertia(j,k);
        end
    end
end

% base cartesian position and orientation (quaternion)
basec.x  = [0.0,0.0,0.0];
basec.xd = [0.0,0.0,0.0];
basec.xdd = [0.0,0.0,0.0];
baseo.q = [0.0,1.0,0.0,0.0];
baseo.qd = [0.0,0.0,0.0,0.0];
baseo.qdd = [0.0,0.0,0.0,0.0];
baseo.ad = [0.0,0.0,0.0];
baseo.add = [0.0,0.0,0.0];

% We observe all joints and all joint velocities
PAR.links = links;
PAR.link0 = link0;
PAR.eff = eff;
PAR.basec = basec;
PAR.baseo = baseo;
PAR.uex = uex;
PAR.uex0 = uex0;
PAR.C = eye(SIM.dimy,SIM.dimx);

% form constraints
CON = [];

% Set FB gains yourself - e.g. PD control
% loading from the gains.cf file 
K(1,1) = 200.0;
K(1,8) = 7.0;
K(2,2) = 300.0;
K(2,9) = 15.0;
K(3,3) = 100.0;
K(3,10) = 5.0;
K(4,4) = 50.0;
K(4,11) = 2.5;
K(5,5) = 10.0;
K(5,12) = 0.3;
K(6,6) = 10.0;
K(6,13) = 0.3;
K(7,7) = 2.5;
K(7,14) = 0.075;
% TODO: load also u_max limits!

% cost structure
% only penalize positions
Q1 = 1*diag([ones(1,4),0.1*ones(1,3),0*ones(1,4),0*ones(1,3)]);
Q2 = 1*diag([ones(1,4),1*ones(1,3),0.1*ones(1,4),0.1*ones(1,3)]);
COST.Q = Q2;
COST.R = 0.01 * eye(SIM.dimu);

% initialize model
wam = BarrettWAM(PAR,CON,COST,SIM);

%% Generate inputs for a desired trajectory

% basis functions of DMPs
bfs = 50;
% % load imitation-learned DMPs from MAT file
% load('dmps.mat','dmps');
% 
% % save dmp weights for later use
% w_origin = zeros(length(dmps),bfs);
% for i = 1:length(dmps)
%     w_origin(i,:) = dmps(i).FORCE.w;
% end
% 
% % center of the region
% t = 0.005:0.005:1.500;
% q0 = [1.8; -0.0011;	-0.106;	1.89; -1.58; 0.149;	0.246];
% g0 = [1.5172; 0.0637; -0.7906; 2.1683; -2.2159; -0.5760; 0.3933];
% 
% [dmp,ref] = adaptDMP(q0,g0,dmps,w_origin);
% % get derivatives of dmps
% [ddmp,dref] = diffDMP(zeros(7,1),zeros(7,1),dmp);
% % combine them
% for i = 1:N_DOFS,dmp(N_DOFS+i) = ddmp(i); end
% ref = [ref; dref];

% load percentage of trajectory from dmp file 
%file = [prefs_folder,'dmp_strike.txt'];
file = 'dmp.txt';
M = dlmread(file);
perc = 0.2; % learning on whole traj can be unstable unless LQR is used
len = size(M,1);
M = M(1:(len * perc),:);
t = M(:,1); t = t';
% order for refs in file: q1 qd1, ...
% switching to order: q1 ... q7, qd1, ..., qd7
q = M(:,2:2:2*N_DOFS);
qd = M(:,3:2:2*N_DOFS+1);
ref = [q';qd'];

% generate u_ff inputs with inverse dynamics
%traj = wam.generateInputs(t,ref); % trajectory generated in joint space

[traj,dmp] = wam.generateInputsWithDMP(t,bfs,ref); % trajectory generated in joint space

% Generate feedback with LQR
wam.generateFeedback(traj);
% PD control
%N = length(t) - 1;
%for i = 1:N, FB(:,:,i) = -K; end
%traj.K = FB;

%% Evolve system dynamics and animate the robot arm

q0 = traj.s(:,1);
% add zero velocity as disturbance
%q0(N_DOFS+1:end) = 0;
% observe output
%qact = wam.evolve(t,q0,traj.unom);
% observe with feedback
[qact,ufull] = wam.observeWithFeedbackErrorForm(traj,q0);
% add performance to trajectory
%traj.addPerformance(traj.unom,qact,wam.COST,'Inverse Dynamics');
traj.addPerformance(ufull,qact,wam.COST,'ID + FB');

% Plot the controls and animate the robot arm
wam.plot_inputs(traj);
wam.plot_outputs(traj);
%wam.animateArm(qact(1:2:2*N_DOFS-1,:),ref);

%% Start learning with ILC

num_trials = 5;
%ilc = wILC(traj,wam,'t');
ilc = wILC(traj,wam,'dmp');

for i = 1:num_trials
    % get next inputs
    %traj2 = ilc.feedforward(traj,[],qact);   
    dmp = ilc.feedforward(traj,dmp,qact);  
    % get the measurements
    %qact = wam.observeWithFeedbackErrorForm(traj2,q0);
    qact = wam.observeWithFeedbackErrorForm(traj,q0,dmp);
    traj.addPerformance([],qact,wam.COST,ilc);
    % Plot the controls and animate the robot arm
    %wam.animateArm(qact(1:2:2*N_DOFS-1,:),ref);
end

% Plot the controls and animate the robot arm
wam.plot_inputs(traj);
wam.plot_outputs(traj);
%wam.animateArm(qact(1:2:2*N_DOFS-1,:),ref);