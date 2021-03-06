function [xtrack,ztrack,xmtrack,zmtrack,w,sdrift] = nls_stepper_periodic_1d(K,ad,anl,cg,k0,kval,Om,om,sig,ep,tf,dt)

    % Llx is domain size, i.e. solve on domain [-Llx,Llx]
    % sig is -1 for bright/focusing, +1 for dark/defocusing
    % tf is total simulation time
    % mu is magnitude of damping on envelope of dark initial condition
        nmax = round(tf/dt); % Step size for time integrator and number of time steps
        Tval = 2*ellipke(kval^2);
        X = (-Tval:Tval/K:Tval-Tval/K)'; % Spatial mesh
        Kvec = pi/Tval*[0:K -K+1:-1]';
        Dx = 1i*Kvec;
    
        scfac2 = dt*pi/Tval;
        cgsc = pi*cg/(ep*Tval);
        s = sign(k0);
        
        avspd = om^2*(2*s*Om-om)/(1+cg*om) - 2*k0*Om*(1 + (1-s*om/Om)^2);
        disp('Lagrangian Speed')
        disp(avspd*2*abs(ad/anl))
        disp('Stokes Drift Speed')
        disp((-2*k0*Om*(1 + (1-s*om/Om)^2))*(2*abs(ad/anl)))
        % Bright/Focusing initial conditions

        if ad/anl > 0
            [~,cnvals,~] = ellipj(X,kval^2);
            uint = kval*sqrt(2*ad/anl)*cnvals; 
            tfac = exp(-1i*ad*(1-2*kval^2)*dt/2);
            tfac2 = exp(-1i*ad*(1-2*kval^2)*dt);            
        else
            [snvals,~,~] = ellipj(X,kval^2);
            uint = kval*sqrt(-2*ad/anl)*snvals; 
            tfac = exp(-1i*ad*(1+kval^2)*dt/2);
            tfac2 = exp(-1i*ad*(1+kval^2)*dt);
        end
        
        [a1,a2,a3,b3] = nls_expan_params(k0,Om,om,sig);
        a12 = (2*cg*k0*(Om-s*om)-2*s*om*Om + Om^2 + om^2/2 +(1+om*cg+12*sig*k0^2-4*s*cg*Om)*a1)/(k0+om*Om-2*s*Om^2+4*sig*k0^3);
        a31 = -( (3*k0*om^2+12*Om^2*k0-18*Om*k0*s*om)*a1 + 9/2*k0^5*sig - 3*Om^2*k0^2*s-3*k0^2*s*om^2+6*Om*k0^2*om)/(3*k0+3*Om*om - 9*s*Om^2 + 27*sig*k0^3);
        n00 = om*(2*Om*s-om)/(1+cg*om);
        n011 = -cg*(2*s*Om-om)/(1+om*cg);
        n012 = 1i*ad*n00*(om/(1+om*cg) + s*cg/(s*cg^2-3*k0*sig));
        
        w = fft(uint); 
        dxuint = ifft(Dx.*w);
        Hdxuint = ifft(abs(Dx).*w);
        
        n0 = real(n00*abs(uint).^2 + ep*(n011*Hdxuint + n012*(uint.*conj(dxuint)-conj(uint).*dxuint)));
        n2 = a1*uint.^2+1i*ep*a12*uint.*dxuint;
        n3 = a31*uint.^3;
        
        sint = ep^2*n0 + 2*ep*real(uint.*exp(1i*k0*X/ep) + ep*n2.*exp(2*1i*k0*X/ep) + ep^2*n3.*exp(3*1i*k0*X/ep));           
        
        Nvorts = 2;
        Lind = K;
        Rind = K+2;
        
        xint1 = pi/Tval*(X(Lind) + Tval);
        xint2 = pi/Tval*(X(Rind) + Tval);
        
        xpos = [xint1; xint2];
        zpos = [sint(Lind);sint(Rind)];
        
        xmpos = [xint1; xint2];
        zmpos = [ep^2*n0(Lind); ep^2*n0(Rind)];
        %zmpos = [0; 0];
        
        xtrack = zeros(Nvorts,nmax+1);
        ztrack = zeros(Nvorts,nmax+1);
        
        xmtrack = zeros(Nvorts,nmax+1);
        zmtrack = zeros(Nvorts,nmax+1);
        
        sdrift = zeros(nmax+1,2);
                 
        sdrift(1,1) = Stokes_Drift_mean(Tval*xmpos(1)/pi,Tval,w,K,s,Om,om,k0);
        sdrift(1,2) = Stokes_Drift_mean(Tval*xmpos(2)/pi,Tval,w,K,s,Om,om,k0);
                
        xtrack(:,1) = (-Tval + Tval/pi*xpos)/ep;
        ztrack(:,1) = zpos;   
        
        xmtrack(:,1) = (-Tval + Tval/pi*xmpos)/ep;
        zmtrack(:,1) = zmpos;   
                
    % Solve NLS equation in time
    
        for nn=1:nmax
            
            t = (nn-1)*dt;
            af = w*tfac;
            cf = w*tfac2;
            
            wc = ifft(w);
            dxwc = ifft(Dx.*w);
            Hdxwc = ifft(abs(Dx).*w);
            
            wph = wc*tfac;
            dxwph = dxwc*tfac;
            Hdxwph = Hdxwc*tfac;
            
            wpf = wc*tfac2;
            dxwpf = dxwc*tfac2;
            Hdxwpf = Hdxwc*tfac2;
            
            for jj = 1:Nvorts
            
                xwave = Tval/pi*xpos(jj) - Tval;
                xlocpos = xloc_calc(xpos(jj),cgsc,t,Tval);
                xlocmpos = xloc_calc(xmpos(jj),cgsc,t,Tval);
                theta = exp(1i*(k0*xwave + Om*t/ep)/ep);
                indc = loc_find(xlocpos,X);
                indcm = loc_find(xlocmpos,X);
                wval = wc(indc);
                dxwval = dxwc(indc);
                Hdxwal = Hdxwc(indc);
                wmval = wc(indcm);
                
                n0 = real(n00*abs(wval)^2 + ep*(n011*Hdxwal + n012*(wval*conj(dxwval)-conj(wval)*dxwval)));        
                n2 = a1*wval.^2 + ep*1i*a12*wval.*dxwval;
                n3 = a31*wval.^3;
                zval = ep^2*n0 + 2*ep*real(wval.*exp(1i*(k0*xwave/ep+ Om*t/ep^2)) + ep*n2.*exp(2*1i*(k0*xwave/ep+ Om*t/ep^2)) + ep^2*n3.*exp(3*1i*(k0*xwave/ep+ Om*t/ep^2)) );
                
                xdot = phi_eval_1d(theta,Tval*(xpos(jj)+cgsc*t)/pi,zval,Tval,w,K,s,cg,Om,om,k0,sig,ad,anl,ep);
                
                ax = scfac2*(om*zval/ep + xdot);
                amx = ep*scfac2*avspd*abs(wmval)^2;
                
                xwave = Tval/pi*(xpos(jj)+ax/2) - Tval;
                xlocpos = xloc_calc(xpos(jj)+ax/2,cgsc,t+dt/2,Tval);
                xlocmpos = xloc_calc(xmpos(jj)+amx/2,cgsc,t+dt/2,Tval);
                theta = exp(1i*(k0*xwave + Om*(t+dt/2)/ep)/ep);
                indc = loc_find(xlocpos,X);
                indcm = loc_find(xlocmpos,X);
                wval = wph(indc);
                dxwval = dxwph(indc);
                Hdxwal = Hdxwph(indc);
                wmval = wph(indcm);
                
                n0 = real(n00*abs(wval)^2 + ep*(n011*Hdxwal + n012*(wval*conj(dxwval)-conj(wval)*dxwval)));        
                n2 = a1*wval.^2 + ep*1i*a12*wval.*dxwval;
                n3 = a31*wval.^3;
                zval = ep^2*n0 + 2*ep*real(wval.*exp(1i*(k0*xwave/ep+ Om*t/ep^2)) + ep*n2.*exp(2*1i*(k0*xwave/ep+ Om*t/ep^2)) + ep^2*n3.*exp(3*1i*(k0*xwave/ep+ Om*t/ep^2)) );
                            
                xdot = phi_eval_1d(theta,Tval*(xpos(jj)+cgsc*(t+dt/2)+ax/2)/pi,zval,Tval,af,K,s,cg,Om,om,k0,sig,ad,anl,ep);
                 
                bx = scfac2*(om*zval/ep + xdot);
                bmx = ep*scfac2*avspd*abs(wmval)^2;
                
                xwave = Tval/pi*(xpos(jj) + bx/2) - Tval;
                xlocpos = xloc_calc(xpos(jj)+bx/2,cgsc,t+dt/2,Tval);
                xlocmpos = xloc_calc(xmpos(jj)+bmx/2,cgsc,t+dt/2,Tval);
                theta = exp(1i*(k0*xwave + Om*(t+dt/2)/ep)/ep);
                indc = loc_find(xlocpos,X);
                indcm = loc_find(xlocmpos,X);
                wval = wph(indc);
                dxwval = dxwph(indc);
                Hdxwal = Hdxwph(indc);
                wmval = wph(indcm);
                
                n0 = real(n00*abs(wval)^2 + ep*(n011*Hdxwal + n012*(wval*conj(dxwval)-conj(wval)*dxwval)));        
                n2 = a1*wval.^2 + ep*1i*a12*wval.*dxwval;
                n3 = a31*wval.^3;
                zval = ep^2*n0 + 2*ep*real(wval.*exp(1i*(k0*xwave/ep+ Om*t/ep^2)) + ep*n2.*exp(2*1i*(k0*xwave/ep+ Om*t/ep^2)) + ep^2*n3.*exp(3*1i*(k0*xwave/ep+ Om*t/ep^2)) );
                
                xdot = phi_eval_1d(theta,Tval*(xpos(jj)+cgsc*(t+dt/2)+bx/2)/pi,zval,Tval,af,K,s,cg,Om,om,k0,sig,ad,anl,ep);
                                
                cx = scfac2*(om*zval/ep + xdot);
                cmx = ep*scfac2*avspd*abs(wmval)^2;
                
                xwave = Tval/pi*(xpos(jj) + cx) - Tval;
                xlocpos = xloc_calc(xpos(jj)+cx,cgsc,t+dt,Tval);
                xlocmpos = xloc_calc(xmpos(jj)+cmx,cgsc,t+dt,Tval);
                theta = exp(1i*(k0*xwave + Om*(t+dt)/ep)/ep);
                indc = loc_find(xlocpos,X);
                indcm = loc_find(xlocmpos,X);
                wval = wpf(indc);
                dxwval = dxwpf(indc);
                Hdxwal = Hdxwpf(indc);
                wmval = wph(indcm);
                                
                n0 = real(n00*abs(wval)^2 + ep*(n011*Hdxwal + n012*(wval*conj(dxwval)-conj(wval)*dxwval)));        
                n2 = a1*wval.^2 + ep*1i*a12*wval.*dxwval;
                n3 = a31*wval.^3;
                zval = ep^2*n0 + 2*ep*real(wval.*exp(1i*(k0*xwave/ep+ Om*t/ep^2)) + ep*n2.*exp(2*1i*(k0*xwave/ep+ Om*t/ep^2)) + ep^2*n3.*exp(3*1i*(k0*xwave/ep+ Om*t/ep^2)) );
                
                xdot = phi_eval_1d(theta,Tval*(xpos(jj)+cgsc*(t+dt)+cx)/pi,zval,Tval,cf,K,s,cg,Om,om,k0,sig,ad,anl,ep);
                
                dx = scfac2*(om*zval/ep + xdot);
                dmx = ep*scfac2*avspd*abs(wmval)^2;
                
                xpos(jj) = xpos(jj) + (ax + 2*(bx+cx) + dx)/6;
                zpos(jj) = zval;                  
                
                xlocmpos = Tval/pi*(xmpos(jj)+cgsc*(t+dt)+cmx) - Tval;
                indcm = loc_find(xlocmpos,X);
                wmval = wph(indcm);
                n0 = n00*abs(wmval).^2;        
                                
                xmpos(jj) = xmpos(jj) + (amx + 2*(bmx+cmx) + dmx)/6;
                zmpos(jj) = ep^2*n0;
                 
            end    
            
            w = w*tfac2;                
            
            xtrack(:,nn+1) = (-Tval + Tval*xpos/pi)/ep;
            ztrack(:,nn+1) = zpos;
            
            xmtrack(:,nn+1) = (-Tval + Tval*xmpos/pi)/ep;
            zmtrack(:,nn+1) = zmpos;
                        
            for jj=1:Nvorts
               sdrift(nn,jj) = Stokes_Drift_mean(Tval*(xmpos(jj)+cgsc*(t+dt))/pi,Tval,w,K,s,Om,om,k0); 
            end
                        
        end
        
        wp = ifft(w);
        no_cells = 1+mod(round(abs(cg)*(t+dt)/ep*K/Tval),2*K);
        wp = wp([no_cells:2*K 1:no_cells-1]');
        n0 = n00*abs(wp).^2;        
        n2 = a1*wp.^2;
        w = ep^2*n0 + 2*ep*real( wp.*exp(1i*(k0*X/ep+ Om*(t+dt)/ep^2)) + ep*n2.*exp(2*1i*(k0*X/ep+ Om*(t+dt)/ep^2)) );            
            
end