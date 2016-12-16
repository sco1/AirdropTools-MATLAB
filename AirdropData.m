classdef AirdropData < handle
    % Top level class definition for various helper methods
    % e.g. Data windowing, trimming, etc. so we're not copy/pasting things
    % between class definitions
    properties
    end
    
    methods
        function [dataObj] = AirdropData()
            if nargout == 0
                clear dataObj
            end
        end
    end
    
    methods (Static)
        function [date] = getdate()
            % Generate current local timestamp and format according to
            % ISO 8601: yyyy-mm-ddTHH:MM:SS+/-HH:MMZ
            if ~verLessThan('MATLAB', '8.4')  % datetime added in R2014b
                timenow = datetime('now', 'TimeZone', 'local');
                formatstr = sprintf('yyyy-mm-ddTHH:MM:SS%sZ', char(tzoffset(timenow)));
            else
                UTCoffset = -java.util.Date().getTimezoneOffset/60;  % See what Java thinks your TZ offset is
                timenow = clock;
                formatstr = sprintf('yyyy-mm-ddTHH:MM:SS%i:00Z', UTCoffset);
            end
            
            date = datestr(timenow, formatstr);
        end
        
        
        function [nlines] = countlines(filepath)
            % COUNTLINES counts the number of lines present in the 
            % specified file, filepath, passed as an absolute path.
            fID = fopen(filepath, 'rt');
            
            blocksize = 16384;  % Size of block to read in, bytes
            nlines = 0;
            while ~feof(fID)
                % Read in CSV file as binary file in chunks, count the
                % number of line feed characters (ASCII 10)
                nlines = nlines + sum(fread(fID, blocksize, 'char') == char(10));
            end
            
            fclose(fID);
        end
        
        
        function [dataidx] = windowdata(ls, waitboxBool)
            % WINDOWDATA generates two draggable vertical lines in the 
            % parent axes of the input lineseries, ls, for the user to
            % use to window the data plotted with the lineseries.
            % 
            % Execution is blocked by UIWAIT and MSGBOX to allow the user 
            % to zoom/pan the axes and manipulate the window lines as 
            % desired. Once the dialog is closed the data indices of the 
            % window lines in the XData of the input lineseries is returned
            % as dataidx.
            %
            % An optional secondary boolean input can be provided to
            % control whether or not execution is blocked by UIWAIT and
            % MSGBOX or simpy by UIWAIT. If waitboxbool is passed as false,
            % only UIIWAIT is called and it is assumed that the user has
            % something else set up to call UIRESUME to resume MATLAB's
            % execution. If waitboxbool is not false or does not exist,
            % UIWAIT and MSGBOX are used to block execution until the
            % dialog box is closed.
            h.ls = ls;
            h.ax = h.ls.Parent;
            h.fig = h.ax.Parent;
            
            oldbuttonup = h.fig.WindowButtonUpFcn;  % Store existing WindowButtonUpFcn
            h.fig.WindowButtonUpFcn = @AirdropData.stopdrag;  % Set the mouse button up Callback
            
            % Create our window lines, set the default line X locations at
            % 25% and 75% of the axes limits
            currxlim = xlim(h.ax);
            axeswidth = currxlim(2) - currxlim(1);
            leftx = axeswidth*0.25;
            rightx = axeswidth*0.75;
            h.dragline(1) = line(ones(1, 2)*leftx, ylim(h.ax), 'Color', 'g', ...
                                 'ButtonDownFcn', @(s,e)AirdropData.startdrag(s, h));
            h.dragline(2) = line(ones(1, 2)*rightx, ylim(h.ax), 'Color', 'g', ...
                                 'ButtonDownFcn', @(s,e)AirdropData.startdrag(s, h));
            
            % Add a background patch to highlight the currently windowed region
            currylim = ylim(h.ax);
            vertices = [leftx,  currylim(1); ...  % Bottom left corner
                        rightx, currylim(1); ...  % Bottom right corner
                        rightx, currylim(2); ...  % Top right corner
                        leftx,  currylim(2)];     % Top left corner
            h.bgpatch = patch('Vertices', vertices, 'Faces', [1 2 3 4], ...
                              'FaceColor', 'green', 'FaceAlpha', 0.05, 'EdgeColor', 'none');
            uistack(h.bgpatch, 'bottom');  % Make sure we're not covering the draglines
            listen.patchx = addlistener(h.dragline, 'XData', 'PostSet', @(s,e)AirdropData.updatebgpatch(h));
            listen.patchy = addlistener(h.dragline, 'XData', 'PostSet', @(s,e)AirdropData.updatebgpatch(h));
            
            % Add appropriate listeners to the X and Y axes to ensure
            % window lines are visible and the appropriate height
            listen.x = addlistener(h.ax, 'XLim', 'PostSet', @(s,e)AirdropData.checklinesx(h));
            listen.y = addlistener(h.ax, 'YLim', 'PostSet', @(s,e)AirdropData.changelinesy(h));
            
            % Unless passed a secondary, False argument, use uiwait to 
            % allow the user to manipulate the axes and window lines as 
            % desired. Otherwise it is assumed that uiresume is called
            % elsewhere to unblock execution
            if nargin == 2 && ~waitboxBool
                uiwait
            else
                uiwait(msgbox('Window Region of Interest Then Press OK'))
            end
            
            % Set output
            dataidx(1) = find(ls.XData >= h.dragline(1).XData(1), 1);
            dataidx(2) = find(ls.XData >= h.dragline(2).XData(1), 1);
            
            dataidx = sort(dataidx);
            
            % Clean up
            delete([listen.x listen.y]);
            delete([listen.patchx listen.patchy]);
            delete([h.dragline h.bgpatch]);
            h.fig.WindowButtonUpFcn = oldbuttonup;
        end


        function [dataidx] = fixedwindowdata(ls, windowlength, waitboxBool)
            % FIXEDWINDOWDATA generates a draggable rectangular patch in 
            % the parent axes of the input lineseries, ls, for the user to
            % use to window the data plotted with the lineseries. The
            % length of the data window, windowlength, is used under the
            % assumption that the input lineseries is a time vs. data plot
            % where time is in seconds.
            % 
            % Execution is blocked by UIWAIT and MSGBOX to allow the user 
            % to zoom/pan the axes and manipulate the window lines as 
            % desired. Once the dialog is closed the data indices of the 
            % window lines in the XData of the input lineseries is returned
            % as dataidx.
            %
            % An optional secondary boolean input can be provided to
            % control whether or not execution is blocked by UIWAIT and
            % MSGBOX or simpy by UIWAIT. If waitboxbool is passed as false,
            % only UIIWAIT is called and it is assumed that the user has
            % something else set up to call UIRESUME to resume MATLAB's
            % execution. If waitboxbool is not false or does not exist,
            % UIWAIT and MSGBOX are used to block execution until the
            % dialog box is closed.
            ax = ls.Parent;
            fig = ax.Parent;
            
            oldbuttonup = fig.WindowButtonUpFcn;  % Store existing WindowButtonUpFcn
            fig.WindowButtonUpFcn = @AirdropData.stopdrag;  % Set the mouse button up Callback
            
            % TODO: Check to make sure the window width isn't wider than
            % the width of the plotted data
            
            currxlim = xlim(ax);
            currylim = ylim(ax);
            axeswidth = currxlim(2) - currxlim(1);

            leftx = axeswidth*0.25;
            rightx = leftx + windowlength;
            vertices = [leftx, currylim(1); ...   % Bottom left corner
                        rightx, currylim(1); ...  % Bottom right corner
                        rightx, currylim(2); ...  % Top right corner
                        leftx, currylim(2)];      % Top left corner
            dragpatch = patch('Vertices', vertices, 'Faces', [1 2 3 4], ...
                                'FaceColor', 'green', 'FaceAlpha', 0.05, ...
                                'ButtonDownFcn', {@AirdropData.startdragwindow, ax, ls});
                            
            % Add a listener to the XData of the drag patch to make sure
            % its width doesn't get adjusted. Seems to be triggered by the
            % data boundary check on drag, but I can't narrow down the 
            % specific issue. This mitigates the issue for now
            widthlistener = addlistener(dragpatch, 'XData', 'PostSet', @(s,e)AirdropData.checkdragwindowwidth(e, windowlength));
            
            % Unless passed a tertiary, False argument, use uiwait to 
            % allow the user to manipulate the axes and window lines as 
            % desired. Otherwise it is assumed that uiresume is called
            % elsewhere to unblock execution
            if nargin == 3 && ~waitboxBool
                uiwait
            else
                uiwait(msgbox('Window Region of Interest Then Press OK'))
            end
            
            % Set output
            dataidx(1) = find(ls.XData >= dragpatch.XData(1), 1);
            dataidx(2) = find(ls.XData >= dragpatch.XData(2), 1);
            dataidx = sort(dataidx);
            
            % Clean up
            delete(widthlistener)
            delete(dragpatch)
            fig.WindowButtonUpFcn = oldbuttonup;
        end
    end
    
    methods (Static, Hidden, Access = protected)
        function startdrag(draggedline, h)
            % Helper function for data windowing, sets figure
            % WindowButtonMotionFcn callback to dragline helper
            % while line is being clicked on & dragged
            h.ax.Parent.WindowButtonMotionFcn = @(s,e)AirdropData.linedrag(h.ax, draggedline, h.ls);
        end
        
        
        function stopdrag(hObj, ~)
            % Helper function for data windowing, clears figure window
            % WindowButtonMotionFcn callback when mouse button is released
            % after dragging the line
            hObj.WindowButtonMotionFcn = '';
        end
        
        
        function checklinesx(h)
            % Helper function for data windowing, checks the X indices of
            % the vertical lines to make sure they're still within the X
            % axis limits of the data axes object
            currxlim = h.ax.XLim;
            currlinex(1) = h.dragline(1).XData(1);
            currlinex(2) = h.dragline(2).XData(1);
            
            
            % Set X coordinate of any line outside the axes limits to the
            % axes limit
            if currlinex(1) < currxlim(1)
                h.dragline(1).XData = [1, 1]*currxlim(1);
            end
            
            if currlinex(1) > currxlim(2)
                h.dragline(1).XData = [1, 1]*currxlim(2);
            end
            
            if currlinex(2) < currxlim(1)
                h.dragline(2).XData = [1, 1]*currxlim(1);
            end
            
            if currlinex(2) > currxlim(2)
               h.dragline(2).XData = [1, 1]*currxlim(2);
            end
            
            % Set X coordinate of any line beyond the boundary of the
            % lineseries to the closest boundary
            minX = min(h.ls.XData);
            maxX = max(h.ls.XData);            
            if currlinex(1) < minX
                h.dragline(1).XData = [1, 1]*minX;
            end
            
            if currlinex(1) > maxX
                h.dragline(1).XData = [1, 1]*maxX;
            end
            
            if currlinex(2) < minX
                h.dragline(2).XData = [1, 1]*minX;
            end
            
            if currlinex(2) > maxX
                h.dragline(2).XData = [1, 1]*maxX;
            end 
        end
        
        
        function changelinesy(h)
            % Helper function for data windowing, sets the height of both
            % vertical lines to the height of the axes object
            h.dragline(1).YData = ylim(h.ax);
            h.dragline(2).YData = ylim(h.ax);
        end

        
        function linedrag(ax, draggedline, plottedline)
            % Helper function for data windowing, updates the x coordinate
            % of the dragged line to the current location of the mouse
            % button
            currentX = ax.CurrentPoint(1, 1);
            
            % Prevent dragging outside of the current axes limits
            if currentX < ax.XLim(1)
                draggedline.XData = [1, 1]*ax.XLim(1);
            elseif currentX > ax.XLim(2)
                draggedline.XData = [1, 1]*ax.XLim(2);
            else
                draggedline.XData = [1, 1]*currentX;
            end
            
            minX = min(plottedline.XData);
            maxX = max(plottedline.XData);
            % Prevent dragging outside of the data limits
            if currentX < minX
                draggedline.XData = [1, 1]*minX;
            elseif currentX > maxX
                draggedline.XData = [1, 1]*maxX;
            end
        end
        
        
        function updatebgpatch(h)
            draglinex = sort([h.dragline(1).XData(1), h.dragline(2).XData(1)]);
            currylim = ylim(h.ax);
            h.bgpatch.Vertices = [draglinex(1) currylim(1); ...
                                  draglinex(2) currylim(1); ...
                                  draglinex(2) currylim(2); ...
                                  draglinex(1) currylim(2)];
        end
        
        
        function startdragwindow(patchObj, ed, ax, ls)
            ax.Parent.WindowButtonMotionFcn = @(s,e)AirdropData.dragwindow(ax, patchObj, ls);
            patchObj.UserData = ed.IntersectionPoint(1);  % Store initial click location to find a delta later
        end
        
        
        function dragwindow(ax, patchObj, plottedline)
            oldmouseX = patchObj.UserData;
            newmouseX = ax.CurrentPoint(1);
            patchObj.UserData = newmouseX;
            
            dx = newmouseX - oldmouseX;
            newpatchX = patchObj.XData + dx; 
          
            % Prevent dragging outside of the current axes limits
            if newpatchX(1) < ax.XLim(1)
                newdx = patchObj.XData - ax.XLim(1);
                patchObj.XData = patchObj.XData + newdx;
            elseif newpatchX(2) > ax.XLim(2)
                newdx = patchObj.XData - ax.XLim(2);
                patchObj.XData = patchObj.XData + newdx;
            else
                patchObj.XData = newpatchX;
            end
            
            % Prevent dragging beyond the limits of the plotted lineseries
            minX = min(plottedline.XData);
            maxX = max(plottedline.XData);
            if newpatchX(1) < minX
                newdx = patchObj.XData(1) - minX;  % Subtract from left boundary only
                patchObj.XData = patchObj.XData - newdx;
            elseif newpatchX(2) > maxX
                newdx = patchObj.XData(2) - maxX;  % Subtract from right boundary only
                patchObj.XData = patchObj.XData - newdx;
            end
        end
        
        function checkdragwindowwidth(ed, width)
            badwidth = abs(ed.AffectedObject.XData(1) - ed.AffectedObject.XData(2)) ~= width;
            if badwidth
                ed.AffectedObject.XData(2:3) = [1, 1]*ed.AffectedObject.XData(1) + width;
            end
        end
    end
end