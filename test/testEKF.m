%% Test Extended Kalman filter

clc; clear; close all;
seed = 5; rng(seed);
eps = 1e-4; % covariance 
N = 20;
dt = 0.02;
x0 = rand(3,1);
xd0 = rand(3,1);

loadTennisTableValues;

params.C = Cdrag;
params.g = gravity;
params.zTable = table_z;
params.radius = ball_radius;
params.yNet = dist_to_table - table_y;
params.table_length = table_length;
params.table_width = table_width;
% coeff of restitution-friction vector
params.CFTX = CFTX;
params.CFTY = CFTY;
params.CRT = CRT;
params.ALG = 'RK4';

%% Testing with the table tennis flight model with air drag

x(:,1) = [x0;xd0];
y(:,1) = x(1:3,1);
yNs(:,1) = y(:,1) + sqrt(eps) * randn(3,1);
% symplectic Euler
for i = 2:N
    x(:,i) = discreteBallFlightModel(x(:,i-1),dt,params);
    y(:,i) = x(1:3,i);
    yNs(:,i) = y(:,i) + sqrt(eps) * randn(3,1);
end

% initialize EKF
dim = 6;
C = [eye(3),zeros(3)];
funState = @(x,u,h) discreteBallFlightModel(x,h,params);
% very small but nonzero value for numerical stability
mats.O = eps * eye(dim);
mats.C = C;
mats.M = eps * eye(3);
filter = EKF(dim,funState,mats);
cov_estimate = eps;
filter.initState(x(:,1),cov_estimate);
for i = 1:N-1
    filter.linearize(dt,0);
    filter.update(yNs(:,i),0);
    yEKF(:,i) = C * filter.x;
    filter.predict(dt,0);
end
filter.update(yNs(:,N),0);
xBest = filter.x;
yEKF(:,N) = C * filter.x;

% Extended Kalman Smoother
t = dt * (1:N);
u = zeros(1,N);
filter.initState(x(:,1),cov_estimate);
[xsmooth,~] = filter.smooth(t,yNs,u);
% iter_smooth = 5;
% for i = 1:iter_smooth
%     filter.initState(xsmooth(:,1),cov_estimate);
%     [xsmooth,~] = filter.smooth(t,xsmooth(1:3,:),u);
% end
yEKF_smooth = C * xsmooth;

SSE_ekf = trace((yEKF - y)*(yEKF - y)')
SSE_ekf_smooth = trace((yEKF_smooth - y)*(yEKF_smooth - y)')
SSE_ns = trace((yNs - y)*(yNs - y)')

plot3(y(1,:), y(2,:), y(3,:), 'ks-', ...
      yNs(1,:), yNs(2,:), yNs(3,:), 'b*', ...
      yEKF(1,:), yEKF(2,:), yEKF(3,:), 'rx:', ...
      yEKF_smooth(1,:), yEKF_smooth(2,:), yEKF_smooth(3,:), '-rd');
xlabel('x');
ylabel('y');
zlabel('z');
grid on;
axis tight;
legend('actual','observations','EKF', 'EKF smoother');

%% Effect of initialization on estimation error

% num_iter = 10;
% SSE_ekf_init_error = zeros(num_iter,1);
% 
% % naive initialization based on filtering
% for j = 2:num_iter+1
%     
%     ballData = [dt*(1:j)',yNs(:,1:j)'];
%     ballFun = @(b0,C,g) predictNextBall(b0,C,g,ballData,size(ballData,1));
%     x0 = [yNs(:,1);(yNs(:,2) - yNs(:,1))/dt];
%     fnc = @(x) ballFun(x,Cdrag,gravity);
%     options = optimoptions('lsqnonlin');
%     options.Display = 'final';
%     options.Algorithm = 'levenberg-marquardt';
%     options.MaxFunEvals = 1500;
%     [xinit,err] = lsqnonlin(fnc,x0,[],[],options);
%     ballInit = xinit(1:6);
%     
%     filter.initState(ballInit,cov_estimate);
%     for i = 1:N-1
%         filter.linearize(dt,0);
%         filter.update(yNs(:,i),0);
%         filter.predict(dt,0);
%     end
%     filter.update(yNs(:,N),0);
%     xEKF = filter.x;
%     SSE_ekf_init_error(j-1) = norm(xEKF - x(:,N))^2;
% end
% figure;
% plot(1:num_iter,SSE_ekf_init_error, '-r');
% title('Effect of naive initialization using nonlin-ls on estimation error');
% 
% SSE_ekf_init_error
% SSE_ekf_best_error = norm(xBest - x(:,N))^2