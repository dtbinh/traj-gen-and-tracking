% Dynamic motor primitives

function discreteAccelerationDMP

g = 1;

% alpha_z and beta_z are time constants
alpha_z = 1;
beta_z = 0.25;
alpha_x = 1;

% temporal scaling factor
tau = 1;

% start from z,y nonzero
z0 = 0;
y0 = 0;
x0 = 1;
X0 = [z0;y0;x0];

% forcing function parameters
f.w = [1, 1, 1];
f.c = [2, 1, 0];
f.h = [1, .1, 1];

% time evolution
tspan = [0 10];

options = odeset('RelTol',1e-4,'AbsTol',[1e-4 1e-4 1e-4]);
PAR.time_const = [alpha_z, beta_z, alpha_x];
PAR.scale = tau;
PAR.goal = [g, y0];
PAR.forcing = f;
[t,X] = ode45(@(t,X)dmp1(t,X,PAR),tspan,X0,options);
z = X(:,1);
y = X(:,2);
x = X(:,3);
plot(t,z,'-',t,y,'-.',t,x,t,g*ones(1,length(t)),'r.');
legend('state velocity ydot','state y','phase','goal state');

end

function dX = dmp1(t,X,PAR)

alpha_z = PAR.time_const(1);
beta_z = PAR.time_const(2);
alpha_x = PAR.time_const(3);
tau = PAR.scale;
g = PAR.goal(1);
y0 = PAR.goal(2);
fpar = PAR.forcing;

A = [-alpha_z/tau, -alpha_z*beta_z/tau, 0;
     1/tau, 0, 0;
     0, 0, -alpha_x/tau];

f = forcing(X(3),g,y0,fpar.w,fpar.h,fpar.c);
% forcing function acts on the accelerations
B = [alpha_z*beta_z*g/tau + f/tau; 0; 0];

dX = A*X + B;

end

% basis functions are unscaled gaussians
function phi = basis(x,h,c)
phi = exp(-h * (x - c)^2);
end

% forcing function to drive nonlinear system dynamics
function f = forcing(x,g,y0,w,h,c)

N = length(w);
f = 0;
scale = 0;
for i = 1:N
    f = f + basis(x,h(i),c(i))*w(i)*x;
    scale = scale + basis(x,h(i),c(i));
end

f = f/scale * (g-y0);
end