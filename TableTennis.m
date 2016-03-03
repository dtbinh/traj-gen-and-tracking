%% Table Tennis class for simulating a match between two robots!

classdef TableTennis < handle
    
    properties
        
        % table related parameters
        TABLE
        % net is useful for strategies
        NET
        % ball class
        ball
        % robot 1
        robot1
        % robot 2 (opponent)
        robot2
        % handle structure for drawing animation
        handle
        % draw flag (structure)
        draw
        % noise models (as a structure)
        noise
        % build offline policy (a structure)
        offline
        
    end
    
    methods
        
        %% CONSTRUCTOR
        function obj = TableTennis(wam,wam2,q0,std,draw,train,lookup)
            
            % initialize two robots
            obj.robot1 = wam;
            obj.robot2 = wam2;
            
            % initialize the noise models
            obj.noise.ballInit.pos.std = std.pos;
            obj.noise.ballInit.vel.std = std.vel;
            obj.noise.camera.std = std.camera;
            
            % initialize a ball            
            obj.ball = Ball(0.0,0.0); 
            
            % shall we train an offline lookup table
            obj.offline.train = train;
            obj.offline.use = lookup;
            obj.offline.savefile = 'OfflineTrajGenLookupTable.mat';
            obj.offline.X = [];
            obj.offline.Y = [];
            
            if obj.offline.use
                % load the savefile
                load(obj.offline.savefile,'X','Y');
                obj.offline.X = X;
                obj.offline.Y = Y;
                obj.offline.B = X \ Y;
                obj.offline.GP = [];
            end
                       
            % initialize animation
            obj.draw.flag = draw;
            if draw
                obj.initAnimation(q0);
            else
                obj.handle = [];
            end
            
            loadTennisTableValues();
            % table related values
            obj.TABLE.Z = table_z;
            obj.TABLE.WIDTH = table_width;
            obj.TABLE.LENGTH = table_length;
            obj.TABLE.DIST = dist_to_table;
            % coeff of restitution-friction vector
            obj.TABLE.K = [CFTX; CFTY; -CRT];
            
            % net y value and coeff of restitution of net
            obj.NET.Y = dist_to_table - table_y;
            obj.NET.Xmax = table_width/2 + net_overhang;
            obj.NET.Zmax = table_z + net_height;
            obj.NET.CRN = net_restitution;           
            
        end
        
        %% MAIN LOOP
        
        % first robot practices 
        function numLands = practice(obj,q0,numTimes)
        
            stdPos = obj.noise.ballInit.pos.std;
            stdVel = obj.noise.ballInit.vel.std;
            numLands = 0;
            eps = 0.0;
            maxSimTime = 3.0;
            
            % Init filter
            filter = obj.initFilter();
            
            for i = 1:numTimes                                               
                % initialize a ball
                obj.ball = Ball(stdPos,stdVel);
                % initialize filter state
                filter.initState([obj.ball.pos;obj.ball.vel],eps);
                % play one turn
                obj.play(q0,filter,maxSimTime);                
                % check landing
                if obj.ball.isLANDED
                    numLands = numLands + 1;
                    % build offline policy
                    if obj.offline.train                        
                        obj.offline.X = [obj.offline.X; obj.offline.b0];
                        obj.offline.Y = [obj.offline.Y; obj.offline.xf];
                    end                    
                end
            end
            
            fprintf('Landed %d/%d.\n',numLands,numTimes);
            if obj.offline.train && ~obj.offline.use
                % save them
                X = obj.offline.X;
                Y = obj.offline.Y;
                save(obj.offline.savefile,'X','Y');
            end
        end
        
        % first robot plays solo once
        function play(obj,q0,filter,timeMax)
            
            r1 = obj.robot1;
            dt = 0.01;
            timeSim = 0.0;
            idx = 1;
            maxTime2Hit = 0.6;
            
            WAIT = 0;
            PREDICT = 1;
            HIT = 2;
            FINISH = 3; % only when practicing solo
            stage = WAIT; 
            
            % initialize q and x
            q = q0; qd0 = zeros(7,1);
            [x,xd,o] = r1.calcRacketState([q0;qd0]);

            while timeSim < timeMax      
                
                % evolve ball according to racket and get estimate
                filter = obj.getBallEstimate(dt,filter,x(:,idx),xd(:,idx),o(:,idx));

                % If it is coming towards the robot consider predicting
                velEst = filter.x(4:6);
                if velEst(2) > 0 && stage == WAIT
                    stage = PREDICT;
                end    
                
                if stage == PREDICT
                    predictTime = 1.2;
                    [ballPred,ballTime,numBounce,time2PassTable] = ...
                        obj.predictBall(dt,predictTime,filter);
                    if checkBounceOnOppTable(filter,obj.TABLE)
                        stage = FINISH;
                    end
                end
                
                if stage == PREDICT && time2PassTable <= maxTime2Hit       
                    if numBounce ~= 1
                        disp('Ball is not valid! Not hitting!');
                        stage = FINISH;
                    else
                        idx = 0;
                        stage = HIT;
                        % If we're training an offline model save optimization result
                        if obj.offline.train || obj.offline.use
                            obj.offline.b0 = filter.x';
                        end
                        [q,x,xd,o] = obj.plan(r1,ballPred,ballTime,q0,dt);            
                    end

                end % end predict      
                
                % Move the robot
                if stage == HIT 
                    idx = idx+1;
                end
                % if movement finished revert to waiting
                if idx > size(x,2)
                    idx = size(x,2);
                    stage = FINISH;
                end
                
                if obj.draw.flag
                    obj.updateAnimation(q(:,idx));
                end
                timeSim = timeSim + dt;                
            end
            
            % clear the ball path predicted and robot generated traj
            if obj.draw.flag && isfield(obj.handle,'ballPred')
                set(obj.handle.robotCartesian,'Visible','off');
                set(obj.handle.ballPred,'Visible','off');
            end
        end
        
        %% HITTING STRATEGY METHODS FOR TABLE TENNIS
        
        function [q,x,xd,o] = plan(obj,robot,ballPred,ballTime,q0,dt)
            
            dofs = 7;
            q0dot = zeros(dofs,1);
            time2return = 1.0;
            
            if obj.offline.use
                %val = obj.offline.b0 * obj.offline.B;
                Xs = obj.offline.X;
                Ys = obj.offline.Y;
                bstar = obj.offline.b0;
                N = size(Xs,1);
                % find the closest point among Xs
                diff = repmat(bstar,N,1) - Xs;
                [~,idx] = min(diag(diff*diff'));
                val = Ys(idx,:);
                        
                qf = val(1:dofs)';
                qfdot = val(dofs+1:2*dofs)';
                T = val(end);
            else
                % Calculate ball outgoing velocities attached to each ball pos
                tic
                fast = true;
                % land the ball on the centre of opponents court
                desBall(1) = 0.0;
                desBall(2) = obj.TABLE.DIST - 3*obj.TABLE.LENGTH/4;
                desBall(3) = obj.TABLE.Z;
                time2reach = 0.5; % time to reach desired point on opponents court
                racketDes = calcRacketStrategy(desBall,ballPred,ballTime,time2reach,fast);
                elapsedTimeForCalcDesRacket = toc;
                fprintf('Elapsed time for racket computation: %f sec.\n',...
                    elapsedTimeForCalcDesRacket);

                % Compute traj here
                %VHP = -0.7;
                %[q,qd,qdd] = generate3DTTTwithVHP(robot,VHP,ballPred,ballTime,q0);
                [qf,qfdot,T] = calcOptimalPoly(robot,racketDes,q0,time2return);
            end
            [q,qd,qdd] = obj.generateSpline(dt,q0,q0dot,qf,qfdot,T,time2return);
            [q,qd,qdd] = robot.checkJointLimits(q,qd,qdd);
            [x,xd,o] = robot.calcRacketState([q;qd]);

            if obj.draw.flag
                % Debugging the trajectory generation 
                obj.handle.robotCartesian = scatter3(x(1,:),x(2,:),x(3,:));
                obj.handle.ballPred = scatter3(ballPred(1,:),ballPred(2,:),ballPred(3,:));
            end
        end
        
        %% TRAJECTORY GENERATION FOR TABLE TENNIS
        
        % Generate a striking and a returning trajectory
        % Based on optimization results qf,qfdot,T and given q0,q0dot
        function [q,qd,qdd] = generateSpline(obj,dt,q0,q0dot,qf,qfdot,T,Tret)

            dof = length(q0);
            time2hit = T;
            time2return = Tret;
            Q0 = [q0;q0dot];  
            Qf = [qf;qfdot];
            
            % If we're training an offline model save optimization result
            if obj.offline.train
                obj.offline.xf = [Qf',time2hit];
            end
            
            % round time2hit to nearest dt
            time2hit = dt * ceil(time2hit/dt);

            % GET 3RD DEGREE POLYNOMIALS            
            pStrike = generatePoly3rd(Q0,Qf,dt,time2hit);
            qStrike = pStrike(1:dof,:);
            qdStrike = pStrike(dof+1:2*dof,:);
            qddStrike = pStrike(2*dof+1:end,:);

            pReturn = generatePoly3rd(Qf,Q0,dt,time2return);
            qReturn = pReturn(1:dof,:);
            qdReturn = pReturn(dof+1:2*dof,:);
            qddReturn = pReturn(2*dof+1:end,:);

            q = [qStrike,qReturn];
            qd = [qdStrike,qdReturn];
            qdd = [qddStrike,qddReturn];            

        end
        
        %% FILTERING FOR ROBOTS TO GET BALL OBSERVATION
        
        function filter = initFilter(obj)
            
            % Initialize EKF
            dim = 6;
            eps = 1e-6; %1e-3;
            C = [eye(3),zeros(3)];
            tennisBall = obj.ball;

            params.C = tennisBall.C;
            params.g = tennisBall.g;
            params.zTable = obj.TABLE.Z;
            params.yNet = obj.NET.Y;
            params.table_length = obj.TABLE.LENGTH; 
            params.table_width = obj.TABLE.WIDTH;
            % coeff of restitution-friction vector
            params.CFTX = obj.TABLE.K(1); 
            params.CFTY = obj.TABLE.K(2); 
            params.CRT = -obj.TABLE.K(3);
            params.ALG = 'Euler'; %'RK4'; 

            ballFlightFnc = @(x,u,dt) discreteBallFlightModel(x,dt,params);
            % very small but nonzero value for numerical stability
            mats.O = eps * eye(dim);
            mats.C = C;
            mats.M = eps * eye(3);
            filter = EKF(dim,ballFlightFnc,mats);
            filter.initState([tennisBall.pos(:); tennisBall.vel(:)],eps);
            
        end
        
        function obs = emulateCamera(obj)
            
            std = obj.noise.camera.std;
            obs = obj.ball.pos + std * randn(3,1);
        end
        
        function filter = getBallEstimate(obj,dt,filter,x,xd,o)
            racket.pos = x;
            racket.vel = xd;
            racketRot = quat2Rot(o);
            racket.normal = racketRot(:,3);
            obj.ball.evolve(dt,racket);
            obs = obj.emulateCamera();

            % Estimate the ball state
            filter.linearize(dt,0);
            filter.predict(dt,0);
            filter.update(obs,0);                
        end
        
        %% PREDICTION OF THE BALL 
        
        % Predict the ball path for a fixed seconds into the future
        % maxPredictHorizon indicates the fixed time
        % includes also bounce prediction (num of estimated bounces)

        function [ballPred,ballTime,numBounce,time2PassTable] = ...
                    predictBall(obj,dt,predictHorizon,filter)

            table = obj.TABLE;
            dist_to_table = table.DIST;
            table_length = table.LENGTH;
            table_z = table.Z;
            table_width = table.WIDTH;
            robotTableCenterY = dist_to_table - table_length/4;

            % init necessary variables
            tol = 2e-2;
            predictLen = floor(predictHorizon / dt);
            ballPred = zeros(6,predictLen);       
            ballTime = (1:predictLen) * dt;
            time2PassTable = Inf;

            % save filter state before prediction
            xSave = filter.x;
            PSave = filter.P;

            % comingDown variable is used because z-derivative estimate might not
            % be valid to predict number of bounces correctly
            numBounce = 0;
            comingDown = true;

            for j = 1:predictLen
                %filter.linearize(dt,0);
                filter.predict(dt,0);
                ballPred(:,j) = filter.x;

                % This part is for estimating num of bounces
                if filter.x(3) < table_z + tol && ...
                   abs(filter.x(1)) < table_width/2 && ...
                   abs(filter.x(2) - robotTableCenterY) < table_length/4 && comingDown

                    numBounce = numBounce + 1;
                    comingDown = false;
                else if filter.x(6) < 0 && ~comingDown
                    comingDown = true;
                    end
                end

                % update the time it takes to pass table
                if filter.x(2) > dist_to_table && time2PassTable == Inf
                    time2PassTable = j * dt;
                end

            end

            % revert back to saved state
            filter.initState(xSave,PSave);
            
        end
        
        %% Animation functions here
        function initAnimation(obj,q)       

            % Prepare the animation
            loadTennisTableValues();
            wam = obj.robot1;
            b = obj.ball;

            % get joints, endeffector pos and orientation
            [joint,ee,racket] = wam.drawPosture(q);
            endeff = [joint(end,:); ee];

            figure;
            %uisetcolor is useful here to determine these 3-vectors
            orange = [0.9100 0.4100 0.1700];
            gray = [0.5020 0.5020 0.5020];
            ballSurfX = b.pos(1) + b.MESH.X;
            ballSurfY = b.pos(2) + b.MESH.Y;
            ballSurfZ = b.pos(3) + b.MESH.Z;
            % transform into base coord.
            h.ball = surf(ballSurfX,ballSurfY,ballSurfZ);
            set(h.ball,'FaceColor',orange,'FaceAlpha',1,'EdgeAlpha',0);
            hold on;
            h.robot.joints = plot3(joint(:,1),joint(:,2),joint(:,3),'k','LineWidth',10);
            h.robot.endeff = plot3(endeff(:,1),endeff(:,2),endeff(:,3),'Color',gray,'LineWidth',5);
            h.robot.racket = fill3(racket(1,:), racket(2,:), racket(3,:), 'r');

            obj.handle = h;
            
            title('Ball-robot interaction');
            grid on;
            axis equal;
            xlabel('x');
            ylabel('y');
            zlabel('z');
            tol_x = 0.1; tol_y = 0.1; tol_z = 0.3;
            xlim([-table_x - tol_x, table_x + tol_x]);
            ylim([dist_to_table - table_length - tol_y, tol_y]);
            zlim([table_z - tol_z, table_z + 2*tol_z]);
            legend('ball','robot');
            fill3(T(:,1),T(:,2),T(:,3),[0 0.7 0.3]);
            fill3(net(:,1),net(:,2),net(:,3),[0 0 0]);
            
        end
        
        % update the animation for robot and the ball
        function updateAnimation(obj,q)
            
            % ANIMATE BOTH THE ROBOT AND THE BALL
            b = obj.ball;
            rob = obj.robot1;
            hball = obj.handle.ball;
            hrobotJ = obj.handle.robot.joints;
            hrobotE = obj.handle.robot.endeff;
            hrobotR = obj.handle.robot.racket;
            [joint,ee,racket] = rob.drawPosture(q);
            endeff = [joint(end,:);ee];
    
            % ball
            set(hball,'XData',b.pos(1) + b.MESH.X);
            set(hball,'YData',b.pos(2) + b.MESH.Y);
            set(hball,'ZData',b.pos(3) + b.MESH.Z);

            % robot joints
            set(hrobotJ,'XData',joint(:,1));
            set(hrobotJ,'YData',joint(:,2));
            set(hrobotJ,'ZData',joint(:,3));
            % robot endeffector
            set(hrobotE,'XData',endeff(:,1));
            set(hrobotE,'YData',endeff(:,2));
            set(hrobotE,'ZData',endeff(:,3));
            % robot racket
            set(hrobotR,'XData',racket(1,:));
            set(hrobotR,'YData',racket(2,:));
            set(hrobotR,'ZData',racket(3,:));

            drawnow;
            %pause(0.001);
            
        end
        
    end
    
    
    
    
    
    
    
    
    
    
    
    
    
    
end